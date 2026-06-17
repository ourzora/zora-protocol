import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Address } from "viem";
import { createProgram } from "../test/create-program.js";

// Factory mocks keep the import graph free of the XMTP native binding
// (@xmtp/node-sdk via client.js) and coins-sdk (via wallet.js), so these
// command tests run in any environment.
const fakeClient = {
  address: "0x2222222222222222222222222222222222222222" as Address,
  sync: vi.fn(async () => {}),
  listDms: vi.fn(async () => []),
  readMessages: vi.fn(async () => []),
  sendText: vi.fn(),
  setConsent: vi.fn(async () => {}),
  streamAllMessages: vi.fn(),
  close: vi.fn(async () => {}),
};

vi.mock("../messaging/client.js", () => ({
  createMessagingClient: vi.fn(async () => fakeClient),
}));
vi.mock("../lib/wallet.js", () => ({
  normalizeKey: (k: string) => (k.startsWith("0x") ? k : `0x${k}`),
}));
vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(() => "0x" + "1".repeat(64)),
}));
// The smart-wallet auth provider does Privy SIWE + chain reads; stub it so these
// command tests stay offline. The real createSmartWalletAuth (pure) wraps it.
vi.mock("../messaging/cli-auth-provider.js", () => ({
  createCliSmartWalletProvider: vi.fn(async () => ({
    getSmartWalletAddress: () =>
      "0x3333333333333333333333333333333333333333" as Address,
    getOwnerAddress: () =>
      "0x4444444444444444444444444444444444444444" as Address,
    getOwners: () => [
      {
        ownerAddress: "0x4444444444444444444444444444444444444444" as Address,
        ownerIndex: 1,
      },
    ],
    signHash: async () => `0x${"11".repeat(65)}` as const,
    getAccessToken: async () => "privy.jwt.token",
  })),
}));
vi.mock("../lib/analytics.js", () => ({ track: vi.fn() }));
vi.mock("../messaging/uapi.js", () => ({
  resolveProfiles: vi.fn(async (addrs: Address[]) => {
    const m = new Map();
    for (const a of addrs)
      m.set(a, {
        address: a,
        handle: "alice",
        displayName: "alice",
        avatarUrl: null,
        platformBlocked: false,
      });
    return m;
  }),
  checkNewDmConversationAllowed: vi.fn(async () => ({
    allowed: true,
    retryAfterSeconds: 0,
  })),
  registerXmtpInstallation: vi.fn(async () => {}),
  resolveHandleToAddress: vi.fn(async (value: string) =>
    value.replace(/^@/, "") === "alice"
      ? { ok: true, address: "0x5555555555555555555555555555555555555555" }
      : { ok: false, reason: "not-found" },
  ),
}));

import { createMessagingClient } from "../messaging/client.js";
import {
  checkNewDmConversationAllowed,
  resolveHandleToAddress,
  resolveProfiles,
} from "../messaging/uapi.js";
import { getPrivateKey } from "../lib/config.js";
import { createCliSmartWalletProvider } from "../messaging/cli-auth-provider.js";
import {
  dmCommand,
  sanitizeMessageText,
  messagePreview,
  formatAge,
} from "./dm.js";

const PEER = "0x1111111111111111111111111111111111111111";

describe("message text rendering helpers", () => {
  it("sanitizeMessageText strips escape/control chars but keeps tabs and newlines", () => {
    const input = `a\x1b[31mred\x1b[0m\tb\nc\x07`;
    expect(sanitizeMessageText(input)).toBe("a[31mred[0m\tb\nc");
  });

  it("messagePreview collapses whitespace and truncates", () => {
    expect(messagePreview("hi\n\nthere   world")).toBe("hi there world");
    expect(messagePreview("x".repeat(100)).length).toBe(72);
    expect(messagePreview("x".repeat(100)).endsWith("…")).toBe(true);
  });

  it("formatAge gives compact relative ages", () => {
    const now = 1_700_000_000_000;
    expect(formatAge(now, now)).toBe("just now");
    expect(formatAge(now - 5 * 60_000, now)).toBe("5m ago");
    expect(formatAge(now - 3 * 3_600_000, now)).toBe("3h ago");
    expect(formatAge(now - 2 * 86_400_000, now)).toBe("2d ago");
    expect(formatAge(now - 3 * 7 * 86_400_000, now)).toBe("3w ago");
  });
});

const run = (args: string[]) =>
  createProgram(dmCommand).parseAsync(["dm", ...args, "--json"], {
    from: "user",
  });

describe("dm command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`exit:${code}`);
    });
    fakeClient.sync.mockClear();
    fakeClient.listDms.mockClear();
    fakeClient.readMessages.mockClear();
    fakeClient.sendText.mockReset();
    fakeClient.setConsent.mockClear();
    fakeClient.streamAllMessages.mockReset();
    fakeClient.close.mockClear();
    vi.mocked(createMessagingClient).mockClear();
  });

  afterEach(() => vi.restoreAllMocks());

  const jsonOut = () =>
    JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));

  it("list outputs conversations with resolved handles and closes the client", async () => {
    fakeClient.listDms.mockResolvedValueOnce([
      {
        id: "c1",
        peerAddress: PEER,
        consent: "allowed",
        profile: null,
        lastMessage: null,
      },
    ]);
    await run(["list"]);
    const out = jsonOut();
    expect(out[0].address).toBe(PEER);
    expect(out[0].handle).toBe("alice");
    expect(fakeClient.sync).toHaveBeenCalledWith(["allowed"]);
    expect(fakeClient.close).toHaveBeenCalled();
  });

  it("requests lists unknown-consent conversations", async () => {
    fakeClient.listDms.mockResolvedValueOnce([]);
    await run(["requests"]);
    expect(fakeClient.sync).toHaveBeenCalledWith(["unknown"]);
    expect(fakeClient.listDms).toHaveBeenCalledWith(["unknown"]);
  });

  it("read returns message history oldest-first", async () => {
    fakeClient.readMessages.mockResolvedValueOnce([
      {
        id: "b",
        senderAddress: PEER,
        fromSelf: false,
        text: "second",
        contentType: "xmtp.org/text:1.0",
        sentAtMs: 2000,
      },
      {
        id: "a",
        senderAddress: PEER,
        fromSelf: false,
        text: "first",
        contentType: "xmtp.org/text:1.0",
        sentAtMs: 1000,
      },
    ]);
    await run(["read", PEER]);
    const out = jsonOut();
    expect(out.messages.map((m: { text: string }) => m.text)).toEqual([
      "first",
      "second",
    ]);
  });

  it("send delivers a message and reports success", async () => {
    fakeClient.sendText.mockImplementationOnce(async () => ({
      id: "sent1",
      senderAddress: fakeClient.address,
      fromSelf: true,
      text: "gm",
      contentType: "xmtp.org/text:1.0",
      sentAtMs: 1000,
    }));
    await run(["send", PEER, "gm"]);
    const out = jsonOut();
    expect(out).toMatchObject({ sent: true, to: PEER, text: "gm" });
  });

  it("listen streams incoming messages as JSON and skips self", async () => {
    fakeClient.streamAllMessages.mockImplementationOnce(() =>
      (async function* () {
        yield {
          id: "m0",
          senderAddress: fakeClient.address,
          fromSelf: true,
          text: "my own message",
          contentType: "xmtp.org/text:1.0",
          sentAtMs: 1000,
          peerAddress: PEER,
        };
        yield {
          id: "m1",
          senderAddress: PEER,
          fromSelf: false,
          text: "gm from a peer",
          contentType: "xmtp.org/text:1.0",
          sentAtMs: 2000,
          peerAddress: PEER,
        };
      })(),
    );
    await run(["listen"]);
    // Only the peer message is emitted; the self message is skipped, so the
    // single logged line parses cleanly.
    const out = jsonOut();
    expect(out).toMatchObject({
      address: PEER,
      text: "gm from a peer",
      contentType: "xmtp.org/text:1.0",
    });
    expect(fakeClient.close).toHaveBeenCalled();
  });

  it("enforces the new-conversation gate in smart-wallet mode (Privy token present)", async () => {
    // Capture the gate callback handed to the client and exercise it.
    let passedGate: ((a: Address) => Promise<void>) | undefined;
    fakeClient.sendText.mockImplementationOnce(
      async (_a: Address, _t: string, gate?: (a: Address) => Promise<void>) => {
        passedGate = gate;
        return {
          id: "sent1",
          senderAddress: fakeClient.address,
          fromSelf: true,
          text: "gm",
          contentType: "xmtp.org/text:1.0",
          sentAtMs: 1000,
        };
      },
    );
    await run(["send", PEER, "gm"]);
    expect(passedGate).toBeDefined();
    await passedGate?.(PEER as Address);
    expect(checkNewDmConversationAllowed).toHaveBeenCalledWith(
      PEER,
      "privy.jwt.token",
    );
  });

  it("errors with agent-create guidance when no wallet is configured", async () => {
    const prevEnv = process.env.ZORA_PRIVATE_KEY;
    delete process.env.ZORA_PRIVATE_KEY;
    vi.mocked(getPrivateKey).mockReturnValueOnce(undefined);
    try {
      await expect(run(["list"])).rejects.toThrow("process.exit(1)");
      const out = jsonOut();
      expect(out.error).toContain("No wallet configured");
      expect(createMessagingClient).not.toHaveBeenCalled();
    } finally {
      if (prevEnv !== undefined) process.env.ZORA_PRIVATE_KEY = prevEnv;
    }
  });

  it("hard-errors when smart-wallet auth can't be built", async () => {
    vi.mocked(createCliSmartWalletProvider).mockRejectedValueOnce(
      new Error("Your Zora smart wallet is not deployed yet"),
    );
    await expect(run(["list"])).rejects.toThrow("process.exit(1)");
    const out = jsonOut();
    expect(out.error).toContain("authenticate your Zora smart-wallet inbox");
    expect(createMessagingClient).not.toHaveBeenCalled();
  });

  it("approve sets consent to allowed", async () => {
    await run(["approve", PEER]);
    expect(fakeClient.setConsent).toHaveBeenCalledWith(PEER, "allowed");
  });

  it("deny sets consent to denied", async () => {
    await run(["deny", PEER]);
    expect(fakeClient.setConsent).toHaveBeenCalledWith(PEER, "denied");
  });

  it("rejects an unresolvable peer before creating a client", async () => {
    await expect(run(["read", "not-a-known-handle"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(createMessagingClient).not.toHaveBeenCalled();
    const out = jsonOut();
    expect(out.error).toContain("No Zora account found");
  });

  it("read accepts a @handle, resolving it to an address", async () => {
    fakeClient.readMessages.mockResolvedValueOnce([]);
    await run(["read", "@alice"]);
    expect(fakeClient.readMessages).toHaveBeenCalledWith(
      "0x5555555555555555555555555555555555555555",
      30,
    );
  });

  it("explains when a handle has no DM inbox", async () => {
    vi.mocked(resolveHandleToAddress).mockResolvedValueOnce({
      ok: false,
      reason: "no-inbox",
    });
    await expect(run(["read", "@nobody"])).rejects.toThrow("process.exit(1)");
    expect(jsonOut().error).toContain("doesn't have a Zora DM inbox");
    expect(createMessagingClient).not.toHaveBeenCalled();
  });

  it("send requires non-empty message text", async () => {
    await expect(run(["send", PEER, "   "])).rejects.toThrow("process.exit(1)");
    const out = jsonOut();
    expect(out.error).toContain("required");
  });

  it("send blocks interaction with platform-banned profiles", async () => {
    vi.mocked(resolveProfiles).mockResolvedValueOnce(
      new Map([
        [
          PEER as Address,
          {
            address: PEER as Address,
            handle: "banned-user",
            displayName: "Banned User",
            avatarUrl: null,
            platformBlocked: true,
          },
        ],
      ]),
    );
    await expect(run(["send", PEER, "hello"])).rejects.toThrow("process.exit(1)");
    const out = jsonOut();
    expect(out.error).toContain("blocked");
    expect(out.error).toContain("terms of service");
    expect(fakeClient.sendText).not.toHaveBeenCalled();
  });
});
