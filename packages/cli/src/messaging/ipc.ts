import net from "node:net";
import { chmodSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { getConfigDir } from "../lib/config.js";

/**
 * Local IPC between the long-lived `dm listen` process (the single owner of the
 * XMTP installation) and one-shot `dm` commands. When a listener is running, a
 * one-shot command forwards its operation over a Unix socket so the listener
 * executes it on the ONE shared client — instead of opening a second client /
 * installation, which would diverge in local state (separate MLS stores) and
 * risk multi-process contention on the same database. With no live listener,
 * commands fall back to opening their own client directly.
 */

/** Unix socket the listener serves and one-shot commands dial. */
export const dmSocketPath = (): string =>
  join(getConfigDir(), "xmtp", "dm.sock");

/** A serialized error, carried over IPC so the caller can re-raise it. */
export interface DmIpcError {
  name?: string;
  message: string;
  /** Present for a denied new-conversation gate, so the caller can hint retry. */
  retryAfterSeconds?: number;
}

export interface DmIpcRequest {
  op: string;
  args?: Record<string, unknown>;
}

export interface DmIpcResponse {
  ok: boolean;
  data?: unknown;
  error?: DmIpcError;
}

/**
 * Cap the bytes buffered per connection before a request line completes. A
 * well-formed DM op is a small JSON line; this bounds memory if a buggy or
 * hostile local peer streams data without a newline. Generous — the largest op
 * (`send`) only carries a short reply.
 */
const MAX_IPC_REQUEST_BYTES = 1_000_000;

const toIpcError = (err: unknown): DmIpcError => {
  if (err instanceof Error) {
    const out: DmIpcError = { name: err.name, message: err.message };
    const retry = (err as { retryAfterSeconds?: number }).retryAfterSeconds;
    if (typeof retry === "number") out.retryAfterSeconds = retry;
    return out;
  }
  return { message: String(err) };
};

/**
 * Serve DM operations on the socket for the lifetime of the returned server.
 * `handle` runs each request on the listener's shared client. Requests are
 * newline-delimited JSON; each gets one JSON response line. Returns the server
 * so the caller can `close()` it on shutdown.
 */
export const startDmIpcServer = (
  handle: (req: DmIpcRequest) => Promise<unknown>,
): net.Server => {
  const path = dmSocketPath();
  const dir = dirname(path);
  mkdirSync(dir, { recursive: true });
  // Owner-only. Connecting to this socket runs privileged DM ops (send/approve/
  // revoke) as this user, and the dir also holds the encrypted XMTP stores, so
  // lock both down regardless of the process umask (e.g. 0000 under some CI /
  // container setups). Best-effort: chmod is a no-op on non-POSIX filesystems.
  try {
    chmodSync(dir, 0o700);
  } catch {
    // non-POSIX filesystem — nothing to restrict
  }
  // Clear a stale socket file from a previous (dead) listener before binding.
  try {
    rmSync(path);
  } catch {
    // nothing to remove
  }

  const server = net.createServer((sock) => {
    let buffer = "";
    sock.on("data", (chunk) => {
      buffer += chunk.toString();
      // Drop a connection that floods us without ever completing a line, so a
      // single peer can't grow the buffer without bound.
      if (buffer.length > MAX_IPC_REQUEST_BYTES) {
        sock.destroy();
        return;
      }
      let nl: number;
      while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl);
        buffer = buffer.slice(nl + 1);
        if (!line.trim()) continue;
        void (async () => {
          let res: DmIpcResponse;
          try {
            const req = JSON.parse(line) as DmIpcRequest;
            res = { ok: true, data: await handle(req) };
          } catch (err) {
            res = { ok: false, error: toIpcError(err) };
          }
          if (!sock.destroyed) sock.write(`${JSON.stringify(res)}\n`);
        })();
      }
    });
    sock.on("error", () => {
      /* client hung up mid-request — ignore */
    });
  });
  server.on("error", () => {
    /* bind errors are surfaced to the caller via listen(); ignore post-bind */
  });
  // Restrict the bound socket file to the owner once it exists (same rationale
  // as the dir above). The callback fires on the 'listening' event.
  server.listen(path, () => {
    try {
      chmodSync(path, 0o600);
    } catch {
      // non-POSIX filesystem — nothing to restrict
    }
  });
  return server;
};

/**
 * Send one operation to a running listener and await its response. Returns
 * `null` when no live listener is reachable (socket absent, or stale/refused),
 * so the caller can fall back to running the operation directly.
 */
export const callDmIpc = (
  req: DmIpcRequest,
  timeoutMs = 20_000,
): Promise<DmIpcResponse | null> => {
  const path = dmSocketPath();
  if (!existsSync(path)) return Promise.resolve(null);

  return new Promise((resolve) => {
    const sock = net.createConnection(path);
    let buffer = "";
    let settled = false;
    const finish = (value: DmIpcResponse | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      sock.destroy();
      resolve(value);
    };
    const timer = setTimeout(() => finish(null), timeoutMs);

    sock.on("connect", () => sock.write(`${JSON.stringify(req)}\n`));
    sock.on("data", (chunk) => {
      buffer += chunk.toString();
      const nl = buffer.indexOf("\n");
      if (nl < 0) return;
      try {
        finish(JSON.parse(buffer.slice(0, nl)) as DmIpcResponse);
      } catch {
        finish(null);
      }
    });
    // A stale socket file (listener dead) refuses the connection → fall back.
    sock.on("error", () => finish(null));
  });
};
