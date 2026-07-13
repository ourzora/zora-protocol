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
  listInstallations: vi.fn(async () => []),
  revokeInstallations: vi.fn(async () => {}),
  revokeOtherInstallations: vi.fn(async () => {}),
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
  getConfigDir: vi.fn(() => "/tmp/zora-cli-test"),
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
import type { DmMessage } from "../messaging/types.js";
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
  dmType,
  shouldExecForMessage,
  buildExecPayload,
  selectExecHistory,
  parseDurationMs,
  EXEC_HISTORY_MAX_MESSAGES,
} from "./dm.js";

const PEER = "0x1111111111111111111111111111111111111111";

describe("real-time listener helpers", () => {
  it("dmType labels unknown-consent messages as requests", () => {
    expect(dmType("unknown")).toBe("DM_REQUEST");
    expect(dmType("allowed")).toBe("DM");
    expect(dmType("denied")).toBe("DM");
  });

  describe("shouldExecForMessage (content gate for --exec)", () => {
    const base = { text: "hi", consent: "allowed" as const };
    it("fires for allowed text messages (active DM)", () => {
      expect(shouldExecForMessage(base)).toBe(true);
    });
    it("fires for a new request (unknown consent) — requests wake the agent too", () => {
      expect(shouldExecForMessage({ ...base, consent: "unknown" })).toBe(true);
    });
    it("never fires for denied conversations or non-text messages", () => {
      expect(shouldExecForMessage({ ...base, consent: "denied" })).toBe(false);
      expect(shouldExecForMessage({ text: null, consent: "allowed" })).toBe(
        false,
      );
      expect(shouldExecForMessage({ text: "  ", consent: "allowed" })).toBe(
        false,
      );
    });
  });

  const streamedMsg = {
    id: "m1",
    senderAddress: PEER as Address,
    fromSelf: false,
    text: "hi\x1b[31mthere",
    contentType: "xmtp.org/text:1.0",
    sentAtMs: 0,
    peerAddress: PEER as Address,
    consent: "unknown" as const,
  };

  it("buildExecPayload emits sanitized JSON with type, consent, and null gap", () => {
    const payload = JSON.parse(buildExecPayload(streamedMsg, "@alice"));
    expect(payload.type).toBe("DM_REQUEST");
    expect(payload.consent).toBe("unknown");
    expect(payload.from).toBe("@alice");
    expect(payload.text).toBe("hi[31mthere"); // escape stripped
    expect(payload.history).toEqual([]); // absent → empty, never missing
    expect(payload.hoursSinceLastMessage).toBeNull();
  });

  it("buildExecPayload includes sanitized thread history + gap for context", () => {
    const payload = JSON.parse(
      buildExecPayload(
        streamedMsg,
        "@alice",
        [
          {
            from: "@alice",
            text: "gm\x1b[0m",
            sentAt: "2026-01-01T00:00:00.000Z",
          },
          { from: "me", text: "hey!", sentAt: "2026-01-01T00:00:01.000Z" },
        ],
        5, // hoursSinceLastMessage — a resumed conversation
      ),
    );
    expect(payload.history).toEqual([
      { from: "@alice", text: "gm[0m", sentAt: "2026-01-01T00:00:00.000Z" }, // escape stripped
      { from: "me", text: "hey!", sentAt: "2026-01-01T00:00:01.000Z" },
    ]);
    expect(payload.hoursSinceLastMessage).toBe(5);
  });

  describe("selectExecHistory (thread context for --exec)", () => {
    const NOW = 10_000_000;
    const MIN = 60_000;
    const HOUR = 3_600_000;
    const WINDOW = 30 * MIN; // the default --exec-history window
    const msg = (over: Partial<DmMessage>): DmMessage => ({
      id: "x",
      senderAddress: PEER as Address,
      fromSelf: false,
      text: "t",
      contentType: "xmtp.org/text:1.0",
      sentAtMs: NOW,
      ...over,
    });

    it("active thread: returns the window's messages oldest-first, tags own 'me', no gap", () => {
      const res = selectExecHistory(
        [
          msg({
            id: "b",
            text: "second",
            sentAtMs: NOW - 5 * MIN,
            fromSelf: true,
          }),
          msg({ id: "a", text: "first", sentAtMs: NOW - 10 * MIN }),
        ],
        "cur",
        "@alice",
        NOW,
        WINDOW,
      );
      expect(res.hoursSinceLastMessage).toBeNull();
      expect(res.history.map((h) => [h.from, h.text])).toEqual([
        ["@alice", "first"],
        ["me", "second"],
      ]);
    });

    it("drops messages older than the window when the window has messages", () => {
      const res = selectExecHistory(
        [
          msg({ id: "old", text: "way back", sentAtMs: NOW - 2 * HOUR }),
          msg({ id: "recent", text: "just now", sentAtMs: NOW - 5 * MIN }),
        ],
        "cur",
        "@alice",
        NOW,
        WINDOW,
      );
      expect(res.hoursSinceLastMessage).toBeNull();
      expect(res.history.map((h) => h.text)).toEqual(["just now"]);
    });

    it("resumed thread: empty window falls back to the last N + hours since last message", () => {
      const res = selectExecHistory(
        [
          msg({ id: "a", text: "earlier", sentAtMs: NOW - 6 * HOUR }),
          msg({ id: "b", text: "last thing said", sentAtMs: NOW - 5 * HOUR }),
        ],
        "cur",
        "@alice",
        NOW,
        WINDOW,
      );
      expect(res.hoursSinceLastMessage).toBe(5);
      expect(res.history.map((h) => h.text)).toEqual([
        "earlier",
        "last thing said",
      ]);
    });

    it("fallback keeps only the most recent `fallbackCount` messages", () => {
      const res = selectExecHistory(
        [
          msg({ id: "a", text: "older", sentAtMs: NOW - 6 * HOUR }),
          msg({ id: "b", text: "newer", sentAtMs: NOW - 5 * HOUR }),
        ],
        "cur",
        "@alice",
        NOW,
        WINDOW,
        1,
      );
      expect(res.history.map((h) => h.text)).toEqual(["newer"]);
      expect(res.hoursSinceLastMessage).toBe(5);
    });

    it("excludes non-text events (null-text init/reactions) from context", () => {
      const res = selectExecHistory(
        [
          msg({ id: "init", text: null, sentAtMs: NOW - 3 * MIN }),
          msg({ id: "react", text: "  ", sentAtMs: NOW - 2 * MIN }),
          msg({ id: "real", text: "hello", sentAtMs: NOW - 1 * MIN }),
        ],
        "cur",
        "@alice",
        NOW,
        WINDOW,
      );
      expect(res.history.map((h) => h.text)).toEqual(["hello"]);
    });

    it("first contact: no prior messages → empty, no gap", () => {
      const res = selectExecHistory(
        [msg({ id: "cur", text: "hi", sentAtMs: NOW })],
        "cur",
        "@alice",
        NOW,
        WINDOW,
      );
      expect(res).toEqual({ history: [], hoursSinceLastMessage: null });
    });

    it("caps a busy window at the most recent EXEC_HISTORY_MAX_MESSAGES", () => {
      const n = EXEC_HISTORY_MAX_MESSAGES + 25;
      const msgs = Array.from({ length: n }, (_, i) =>
        msg({ id: `m${i}`, text: `msg ${i}`, sentAtMs: NOW - (n - i) * 1000 }),
      );
      const res = selectExecHistory(msgs, "cur", "@alice", NOW, WINDOW);
      expect(res.history).toHaveLength(EXEC_HISTORY_MAX_MESSAGES);
      expect(res.history[res.history.length - 1].text).toBe(`msg ${n - 1}`);
    });
  });

  describe("parseDurationMs", () => {
    it("parses <n><unit> to milliseconds", () => {
      expect(parseDurationMs("1h")).toBe(3_600_000);
      expect(parseDurationMs("30m")).toBe(1_800_000);
      expect(parseDurationMs("24h")).toBe(86_400_000);
      expect(parseDurationMs("90s")).toBe(90_000);
      expect(parseDurationMs("2d")).toBe(172_800_000);
    });
    it("treats 0 / off / none as disabled", () => {
      expect(parseDurationMs("0")).toBe(0);
      expect(parseDurationMs("off")).toBe(0);
      expect(parseDurationMs("none")).toBe(0);
    });
    it("returns null for a bare number or garbage so the caller can reject it", () => {
      expect(parseDurationMs("10")).toBeNull();
      expect(parseDurationMs("1x")).toBeNull();
      expect(parseDurationMs("abc")).toBeNull();
      expect(parseDurationMs("")).toBeNull();
    });
  });
});

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
    fakeClient.listInstallations.mockClear();
    fakeClient.revokeInstallations.mockClear();
    fakeClient.revokeOtherInstallations.mockClear();
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
    await expect(run(["send", PEER, "hello"])).rejects.toThrow(
      "process.exit(1)",
    );
    const out = jsonOut();
    expect(out.error).toContain("blocked");
    expect(out.error).toContain("terms of service");
    expect(fakeClient.sendText).not.toHaveBeenCalled();
  });

  it("installations lists devices oldest-first with the current flag", async () => {
    fakeClient.listInstallations.mockResolvedValueOnce([
      { id: "inst-current", createdAtMs: 2000, current: true },
      { id: "inst-old", createdAtMs: 1000, current: false },
    ]);
    await run(["installations"]);
    const out = jsonOut();
    expect(out.map((i: { id: string }) => i.id)).toEqual([
      "inst-old",
      "inst-current",
    ]);
    expect(out.find((i: { current: boolean }) => i.current).id).toBe(
      "inst-current",
    );
  });

  it("revoke removes the given installation id", async () => {
    fakeClient.listInstallations.mockResolvedValueOnce([
      { id: "inst-current", createdAtMs: 2000, current: true },
      { id: "inst-old", createdAtMs: 1000, current: false },
    ]);
    await run(["revoke", "inst-old"]);
    expect(fakeClient.revokeInstallations).toHaveBeenCalledWith(["inst-old"]);
  });

  it("revoke refuses to remove the current device", async () => {
    fakeClient.listInstallations.mockResolvedValueOnce([
      { id: "inst-current", createdAtMs: 2000, current: true },
    ]);
    await expect(run(["revoke", "inst-current"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(fakeClient.revokeInstallations).not.toHaveBeenCalled();
  });

  it("revoke --others delegates to revokeOtherInstallations", async () => {
    await run(["revoke", "--others"]);
    expect(fakeClient.revokeOtherInstallations).toHaveBeenCalled();
  });
});
