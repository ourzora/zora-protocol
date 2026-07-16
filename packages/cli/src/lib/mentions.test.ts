import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@zoralabs/coins-sdk", () => ({ getProfile: vi.fn() }));

import { getProfile } from "@zoralabs/coins-sdk";
import {
  formatMention,
  resolveHandleToAddress,
  resolveMentions,
  toPlainMentions,
} from "./mentions.js";

const ADDR = "0x1234567890abcdef1234567890abcdef12345678";

/** A resolver that maps a fixed set of handles to addresses; others are unknown. */
function fakeResolver(map: Record<string, string>) {
  return async (handle: string) => map[handle.toLowerCase()] ?? null;
}

describe("formatMention", () => {
  it("builds a markdown-link token with a lowercased address", () => {
    expect(formatMention("alice", "0xABCDEF")).toBe(
      "[@alice](https://zora.co/@0xabcdef)",
    );
  });
});

describe("toPlainMentions", () => {
  it("renders mention tokens back to plain @handle", () => {
    expect(
      toPlainMentions(`gm [@alice](https://zora.co/@${ADDR}) welcome`),
    ).toBe("gm @alice welcome");
  });

  it("leaves text without mentions untouched", () => {
    expect(toPlainMentions("just a comment")).toBe("just a comment");
  });
});

describe("resolveMentions", () => {
  afterEach(() => vi.clearAllMocks());

  it("returns the text unchanged when there are no mentions", async () => {
    const result = await resolveMentions("gm nice coin", fakeResolver({}));
    expect(result.text).toBe("gm nice coin");
    expect(result.resolved).toEqual([]);
    expect(result.skipped).toEqual([]);
  });

  it("encodes a resolved handle into a mention token", async () => {
    const result = await resolveMentions(
      "gm @alice welcome",
      fakeResolver({ alice: ADDR }),
    );
    expect(result.text).toBe(`gm [@alice](https://zora.co/@${ADDR}) welcome`);
    expect(result.resolved).toEqual([{ handle: "alice", address: ADDR }]);
    expect(result.skipped).toEqual([]);
  });

  it("leaves an unresolved handle as raw text", async () => {
    const result = await resolveMentions("hey @ghost", fakeResolver({}));
    expect(result.text).toBe("hey @ghost");
    expect(result.resolved).toEqual([]);
    expect(result.skipped).toEqual(["ghost"]);
  });

  it("encodes a mention at the start of the text", async () => {
    const result = await resolveMentions(
      "@alice hi",
      fakeResolver({ alice: ADDR }),
    );
    expect(result.text).toBe(`[@alice](https://zora.co/@${ADDR}) hi`);
  });

  it("handles multiple mentions, encoding only the resolved ones", async () => {
    const result = await resolveMentions(
      "@alice and @ghost and @bob",
      fakeResolver({ alice: ADDR, bob: "0xbob" }),
    );
    expect(result.text).toBe(
      `[@alice](https://zora.co/@${ADDR}) and @ghost and [@bob](https://zora.co/@0xbob)`,
    );
    expect(result.resolved.map((r) => r.handle)).toEqual(["alice", "bob"]);
    expect(result.skipped).toEqual(["ghost"]);
  });

  it("does not match an @ inside an email-like token", async () => {
    const result = await resolveMentions(
      "mail me at foo@alice.com",
      fakeResolver({ alice: ADDR }),
    );
    // No whitespace/start before the @, so it isn't treated as a mention.
    expect(result.text).toBe("mail me at foo@alice.com");
    expect(result.resolved).toEqual([]);
  });

  it("resolves each distinct handle only once", async () => {
    const resolver = vi.fn(async () => ADDR);
    await resolveMentions("@alice @alice @Alice", resolver);
    expect(resolver).toHaveBeenCalledTimes(1);
  });

  it("skips a handle whose resolver throws (never blocks posting)", async () => {
    const result = await resolveMentions("hi @alice", async () => {
      throw new Error("network");
    });
    expect(result.text).toBe("hi @alice");
    expect(result.skipped).toEqual(["alice"]);
  });
});

describe("resolveHandleToAddress", () => {
  afterEach(() => vi.clearAllMocks());

  it("prefers the smart wallet over external and public wallets", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "alice",
          publicWallet: { walletAddress: "0xpublic" },
          linkedWallets: {
            edges: [
              { node: { walletType: "EXTERNAL", walletAddress: "0xext" } },
              {
                node: { walletType: "SMART_WALLET", walletAddress: "0xsmart" },
              },
            ],
          },
        },
      },
    } as any);
    expect(await resolveHandleToAddress("alice")).toBe("0xsmart");
  });

  it("falls back to the external wallet, then the public wallet", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "bob",
          publicWallet: { walletAddress: "0xpublic" },
          linkedWallets: {
            edges: [
              { node: { walletType: "EXTERNAL", walletAddress: "0xext" } },
            ],
          },
        },
      },
    } as any);
    expect(await resolveHandleToAddress("bob")).toBe("0xext");

    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "carol",
          publicWallet: { walletAddress: "0xpublic" },
          linkedWallets: { edges: [] },
        },
      },
    } as any);
    expect(await resolveHandleToAddress("carol")).toBe("0xpublic");
  });

  it("returns null when the handle has no profile", async () => {
    vi.mocked(getProfile).mockResolvedValue({ data: { profile: null } } as any);
    expect(await resolveHandleToAddress("ghost")).toBeNull();
  });
});
