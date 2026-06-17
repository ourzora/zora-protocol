import { describe, expect, it, vi } from "vitest";
import type { Address } from "viem";
import {
  NewConversationDeniedError,
  listConversations,
  listRequests,
  readConversation,
  sendReply,
  setConsentForPeer,
  type CoreDeps,
} from "./core.js";
import type {
  DmMessage,
  DmSummary,
  MessagingClient,
  MessagingProfile,
} from "./types.js";

const PEER = "0x1111111111111111111111111111111111111111" as Address;
const SELF = "0x2222222222222222222222222222222222222222" as Address;

const msg = (overrides: Partial<DmMessage> = {}): DmMessage => ({
  id: "m1",
  senderAddress: PEER,
  fromSelf: false,
  text: "hi",
  contentType: "xmtp.org/text:1.0",
  sentAtMs: 1000,
  ...overrides,
});

const summary = (overrides: Partial<DmSummary> = {}): DmSummary => ({
  id: "c1",
  peerAddress: PEER,
  consent: "allowed",
  profile: null,
  lastMessage: null,
  ...overrides,
});

const fakeClient = (
  overrides: Partial<MessagingClient> = {},
): MessagingClient => ({
  address: SELF,
  sync: vi.fn(async () => {}),
  listDms: vi.fn(async () => [summary()]),
  readMessages: vi.fn(async () => [msg()]),
  sendText: vi.fn(async () => msg({ fromSelf: true, senderAddress: SELF })),
  setConsent: vi.fn(async () => {}),
  streamAllMessages: () => (async function* () {})(),
  close: vi.fn(async () => {}),
  ...overrides,
});

const profile = (handle: string): MessagingProfile => ({
  address: PEER,
  handle,
  displayName: handle,
  avatarUrl: null,
});

const fakeDeps = (overrides: Partial<CoreDeps> = {}): CoreDeps => ({
  resolveProfiles: vi.fn(async () => new Map([[PEER, profile("alice")]])),
  checkNewDmConversationAllowed: vi.fn(async () => ({
    allowed: true,
    retryAfterSeconds: 0,
  })),
  ...overrides,
});

describe("listConversations", () => {
  it("syncs allowed, lists, and attaches resolved profiles", async () => {
    const client = fakeClient();
    const deps = fakeDeps();
    const result = await listConversations(client, { token: "jwt", deps });

    expect(client.sync).toHaveBeenCalledWith(["allowed"]);
    expect(client.listDms).toHaveBeenCalledWith(["allowed"]);
    expect(deps.resolveProfiles).toHaveBeenCalledWith([PEER], "jwt");
    expect(result[0]?.profile?.handle).toBe("alice");
  });

  it("skips profile resolution when there are no peer addresses", async () => {
    const deps = fakeDeps();
    const client = fakeClient({
      listDms: vi.fn(async () => [summary({ peerAddress: null })]),
    });
    const result = await listConversations(client, { deps });
    expect(deps.resolveProfiles).not.toHaveBeenCalled();
    expect(result[0]?.profile).toBeNull();
  });
});

describe("listRequests", () => {
  it("syncs and lists unknown-consent conversations", async () => {
    const client = fakeClient({
      listDms: vi.fn(async () => [summary({ consent: "unknown" })]),
    });
    const deps = fakeDeps();
    await listRequests(client, { deps });
    expect(client.sync).toHaveBeenCalledWith(["unknown"]);
    expect(client.listDms).toHaveBeenCalledWith(["unknown"]);
  });
});

describe("readConversation", () => {
  it("returns messages oldest-first with the peer profile", async () => {
    const client = fakeClient({
      readMessages: vi.fn(async () => [
        msg({ id: "newer", sentAtMs: 3000 }),
        msg({ id: "older", sentAtMs: 1000 }),
      ]),
    });
    const deps = fakeDeps();
    const { messages, profile: p } = await readConversation(client, PEER, {
      token: "jwt",
      deps,
    });
    expect(client.sync).toHaveBeenCalledWith(["allowed", "unknown"]);
    expect(messages.map((m) => m.id)).toEqual(["older", "newer"]);
    expect(p?.handle).toBe("alice");
  });
});

describe("sendReply", () => {
  it("gates new conversations when a token is present", async () => {
    const client = fakeClient();
    const deps = fakeDeps();
    await sendReply(client, PEER, "yo", { token: "jwt", deps });

    // The gate callback is passed through to the client.
    const gate = (client.sendText as ReturnType<typeof vi.fn>).mock.calls[0][2];
    expect(typeof gate).toBe("function");
    await gate(PEER);
    expect(deps.checkNewDmConversationAllowed).toHaveBeenCalledWith(
      PEER,
      "jwt",
    );
  });

  it("throws NewConversationDeniedError when the gate denies", async () => {
    const client = fakeClient({
      sendText: vi.fn(async (_addr, _text, gate) => {
        if (gate) await gate(PEER);
        return msg({ fromSelf: true });
      }),
    });
    const deps = fakeDeps({
      checkNewDmConversationAllowed: vi.fn(async () => ({
        allowed: false,
        retryAfterSeconds: 42,
      })),
    });

    await expect(
      sendReply(client, PEER, "yo", { token: "jwt", deps }),
    ).rejects.toMatchObject({
      name: "NewConversationDeniedError",
      retryAfterSeconds: 42,
    });
  });

  it("skips gating entirely without a token (dev/EOA mode)", async () => {
    const client = fakeClient();
    const deps = fakeDeps();
    await sendReply(client, PEER, "yo", { deps });
    const gate = (client.sendText as ReturnType<typeof vi.fn>).mock.calls[0][2];
    expect(gate).toBeUndefined();
    expect(deps.checkNewDmConversationAllowed).not.toHaveBeenCalled();
  });
});

describe("setConsentForPeer", () => {
  it("delegates to the client", async () => {
    const client = fakeClient();
    await setConsentForPeer(client, PEER, "denied");
    expect(client.setConsent).toHaveBeenCalledWith(PEER, "denied");
  });
});

describe("NewConversationDeniedError", () => {
  it("includes the retry hint in its message", () => {
    const err = new NewConversationDeniedError(PEER, 30);
    expect(err.message).toContain("retry after 30s");
  });
});
