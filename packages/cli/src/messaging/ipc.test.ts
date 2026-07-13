import { afterEach, describe, expect, it, vi } from "vitest";
import { once } from "node:events";
import { mkdtempSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Server } from "node:net";

// Serve the socket from a throwaway dir so the tests don't touch the real config.
const DIR = mkdtempSync(join(tmpdir(), "zora-ipc-"));
vi.mock("../lib/config.js", () => ({ getConfigDir: () => DIR }));

import { startDmIpcServer, callDmIpc, dmSocketPath } from "./ipc.js";

describe("dm IPC", () => {
  let server: Server | undefined;
  afterEach(() => {
    server?.close();
    server = undefined;
  });

  const serve = async (
    handle: Parameters<typeof startDmIpcServer>[0],
  ): Promise<void> => {
    server = startDmIpcServer(handle);
    await once(server, "listening");
  };

  it("returns null when no listener is running (fall back to direct)", async () => {
    expect(await callDmIpc({ op: "list" })).toBeNull();
  });

  it("round-trips an op and its result through the listener", async () => {
    await serve(async (req) => ({ echoed: req.op, args: req.args }));
    const res = await callDmIpc({ op: "send", args: { peer: "0xabc" } });
    expect(res?.ok).toBe(true);
    expect(res?.data).toEqual({ echoed: "send", args: { peer: "0xabc" } });
  });

  it("restricts the socket dir and file to the owner", async () => {
    await serve(async () => ({}));
    const sockPath = dmSocketPath();
    // Connecting runs privileged DM ops as this user; keep both owner-only.
    expect(statSync(join(DIR, "xmtp")).mode & 0o777).toBe(0o700);
    expect(statSync(sockPath).mode & 0o777).toBe(0o600);
  });

  it("drops a connection that floods without completing a request line", async () => {
    const handle = vi.fn(async () => ({}));
    await serve(handle);
    const { createConnection } = await import("node:net");
    const sock = createConnection(dmSocketPath());
    await once(sock, "connect");
    // Stream >1MB with no newline; the server should destroy the connection
    // instead of buffering unbounded, and never invoke the handler.
    const closed = once(sock, "close");
    sock.write("x".repeat(1_000_001));
    await closed;
    expect(handle).not.toHaveBeenCalled();
  });

  it("carries an error (with retryAfterSeconds) back to the caller", async () => {
    await serve(async () => {
      const err = new Error("not allowed") as Error & {
        retryAfterSeconds?: number;
      };
      err.name = "NewConversationDeniedError";
      err.retryAfterSeconds = 42;
      throw err;
    });
    const res = await callDmIpc({ op: "send" });
    expect(res?.ok).toBe(false);
    expect(res?.error?.name).toBe("NewConversationDeniedError");
    expect(res?.error?.retryAfterSeconds).toBe(42);
  });
});
