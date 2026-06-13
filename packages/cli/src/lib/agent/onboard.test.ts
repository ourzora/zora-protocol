import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("../privy.js", () => ({
  createPrivyAccount: vi.fn(),
  findEmbeddedWallet: vi.fn(),
}));
vi.mock("./profile.js", () => ({ createAgentProfile: vi.fn() }));
vi.mock("./update-profile.js", () => ({ updateAgentProfile: vi.fn() }));
vi.mock("./zora-client.js", () => ({ ipfsUpload: vi.fn() }));
vi.mock("./smart-wallet.js", () => ({ provisionSmartWallet: vi.fn() }));
vi.mock("./coin.js", () => ({ createCreatorCoin: vi.fn() }));
vi.mock("./post.js", () => ({ createFirstPost: vi.fn() }));

import { onboardAgent } from "./onboard.js";
import { createPrivyAccount, findEmbeddedWallet } from "../privy.js";
import { createAgentProfile } from "./profile.js";
import { updateAgentProfile } from "./update-profile.js";
import { ipfsUpload } from "./zora-client.js";
import { provisionSmartWallet } from "./smart-wallet.js";
import { createCreatorCoin } from "./coin.js";
import { createFirstPost } from "./post.js";

const PK = `0x${"a".repeat(64)}` as const;
const EMBEDDED = "0xEeE0000000000000000000000000000000000001" as const;
const SMART = "0xd1373e4119dD2C4C23f11F9cDc97A464790acbC8" as const;
const noSleep = async () => {};
// First-post inputs: the post is published only when both are supplied, so
// tests that expect a post spread these into the onboardAgent call.
const POST_IMAGE = {
  filename: "bg.png",
  bytes: new Uint8Array([1, 2, 3]),
  mimeType: "image/png",
};
const POST_ARGS = { caption: "gm", postImage: POST_IMAGE } as const;

beforeEach(() => {
  vi.clearAllMocks();
  vi.mocked(createPrivyAccount).mockResolvedValue({
    address: "0xExternal000000000000000000000000000000001",
    did: "did:privy:x",
    accessToken: "tok",
    isNewUser: true,
    linkedAccounts: [],
  });
  vi.mocked(findEmbeddedWallet).mockReturnValue(EMBEDDED);
  vi.mocked(createAgentProfile).mockResolvedValue({
    username: "keen_cedar_9807",
  });
  // By default the update echoes back a profile; individual tests override it.
  vi.mocked(updateAgentProfile).mockResolvedValue({
    username: "keen_cedar_9807",
  });
  vi.mocked(ipfsUpload).mockResolvedValue("ipfs://uploaded-avatar");
  vi.mocked(provisionSmartWallet).mockResolvedValue({
    address: SMART,
    owners: [EMBEDDED, SMART],
  });
  vi.mocked(createCreatorCoin).mockResolvedValue({
    sponsored: true,
    simulation: "ExecutionResult",
    submitted: { hash: "0xco", success: true },
  });
  vi.mocked(createFirstPost).mockResolvedValue({
    sponsored: true,
    simulation: "ExecutionResult",
    submitted: { hash: "0xpo", success: true },
    caption: "gm",
    ticker: "GM",
    imageUri: "ipfs://i",
    contractUri: "ipfs://c",
    coinAddress: "0x1f6835c4996fad83c8af2afa00056adf9234fe72",
  });
});

describe("onboardAgent", () => {
  it("runs all steps and returns the assembled identity", async () => {
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      ...POST_ARGS,
    });
    expect(result.username).toBe("keen_cedar_9807");
    expect(result.smartWallet).toBe(SMART);
    expect(result.embedded).toBe(EMBEDDED);
    expect(result.coin?.hash).toBe("0xco");
    expect(result.post?.hash).toBe("0xpo");
    expect(result.profileUrl).toBe("https://zora.co/@keen_cedar_9807");
    expect(result.post?.url).toBe(
      "https://zora.co/coin/base:0x1f6835c4996fad83c8af2afa00056adf9234fe72",
    );
    expect(createAgentProfile).toHaveBeenCalledTimes(1);
    expect(provisionSmartWallet).toHaveBeenCalledTimes(1);
    expect(createCreatorCoin).toHaveBeenCalledTimes(1);
    expect(createFirstPost).toHaveBeenCalledTimes(1);
  });

  it("re-authenticates until the embedded wallet appears", async () => {
    vi.mocked(findEmbeddedWallet)
      .mockReturnValueOnce(undefined)
      .mockReturnValueOnce(undefined)
      .mockReturnValue(EMBEDDED);
    await onboardAgent({ privateKey: PK, sleep: noSleep });
    expect(
      vi.mocked(createPrivyAccount).mock.calls.length,
    ).toBeGreaterThanOrEqual(3);
  });

  it("throws if the embedded wallet never appears", async () => {
    vi.mocked(findEmbeddedWallet).mockReturnValue(undefined);
    await expect(
      onboardAgent({ privateKey: PK, sleep: noSleep, embeddedAttempts: 2 }),
    ).rejects.toThrow(/embedded wallet/i);
  });

  it("reports isNewUser from the first sign-in, not the re-auth", async () => {
    // A genuinely new user: the first SIWE registers (is_new_user=true), but the
    // re-auth that picks up the embedded wallet returns the same user as a
    // returning one (false). The result must reflect the first sign-in.
    vi.mocked(createPrivyAccount)
      .mockResolvedValueOnce({
        address: "0xExternal000000000000000000000000000000001",
        did: "did:privy:x",
        accessToken: "tok",
        isNewUser: true,
        linkedAccounts: [],
      })
      .mockResolvedValue({
        address: "0xExternal000000000000000000000000000000001",
        did: "did:privy:x",
        accessToken: "tok",
        isNewUser: false,
        linkedAccounts: [],
      });
    vi.mocked(findEmbeddedWallet)
      .mockReturnValueOnce(undefined)
      .mockReturnValue(EMBEDDED);

    const result = await onboardAgent({ privateKey: PK, sleep: noSleep });
    expect(result.isNewUser).toBe(true);
  });

  it("passes dryRun through to the coin + post", async () => {
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      dryRun: true,
      ...POST_ARGS,
    });
    expect(result.dryRun).toBe(true);
    expect(createCreatorCoin).toHaveBeenCalledWith(
      expect.objectContaining({ dryRun: true }),
    );
    // The injected clock must reach createFirstPost so its receipt-poll loop is
    // time-controllable from onboardAgent (no real setTimeout delays in tests).
    expect(createFirstPost).toHaveBeenCalledWith(
      expect.objectContaining({ dryRun: true, sleep: noSleep }),
    );
  });

  it("skips the coin and post when asked", async () => {
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      skipCoin: true,
      skipPost: true,
    });
    expect(createCreatorCoin).not.toHaveBeenCalled();
    expect(createFirstPost).not.toHaveBeenCalled();
    expect(result.coin).toBeUndefined();
    expect(result.post).toBeUndefined();
  });

  it("skips the first post when no caption + image are given", async () => {
    const result = await onboardAgent({ privateKey: PK, sleep: noSleep });
    expect(createFirstPost).not.toHaveBeenCalled();
    expect(result.post).toBeUndefined();
    // The coin still runs — only the post is gated on the caption + image.
    expect(createCreatorCoin).toHaveBeenCalledTimes(1);
  });

  it("forwards caption, image, derived handle, title, and description to the post", async () => {
    await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      ...POST_ARGS,
      postTitle: "My Coin",
      postDescription: "the description",
    });
    expect(createFirstPost).toHaveBeenCalledWith(
      expect.objectContaining({
        caption: "gm",
        image: { bytes: POST_IMAGE.bytes, mimeType: "image/png" },
        handle: "zora.co/keen_cedar_9807",
        title: "My Coin",
        description: "the description",
      }),
    );
  });

  it("keeps the identity (and profile link) when the coin step fails", async () => {
    vi.mocked(createCreatorCoin).mockRejectedValue(new Error("coin boom"));
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      ...POST_ARGS,
    });
    // The account already exists, so a coin failure must not discard it.
    expect(result.username).toBe("keen_cedar_9807");
    expect(result.profileUrl).toBe("https://zora.co/@keen_cedar_9807");
    expect(result.coin).toBeUndefined();
    expect(result.coinError).toMatch(/coin boom/);
    // The post still runs after a coin failure.
    expect(result.post?.hash).toBe("0xpo");
  });

  it("keeps the identity (and profile link) when the post step fails", async () => {
    vi.mocked(createFirstPost).mockRejectedValue(new Error("post boom"));
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      ...POST_ARGS,
    });
    expect(result.profileUrl).toBe("https://zora.co/@keen_cedar_9807");
    expect(result.post).toBeUndefined();
    expect(result.postError).toMatch(/post boom/);
    expect(result.coin?.hash).toBe("0xco");
  });

  it("falls back to the profile URL for the post link when the coin address is unresolved", async () => {
    vi.mocked(createFirstPost).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      submitted: { hash: "0xpo", success: true },
      caption: "gm",
      ticker: "GM",
      imageUri: "ipfs://i",
      contractUri: "ipfs://c",
      // no coinAddress — the resolver couldn't pin the content coin down
    });
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      ...POST_ARGS,
    });
    expect(result.post?.coinAddress).toBeUndefined();
    expect(result.post?.url).toBe("https://zora.co/@keen_cedar_9807");
  });

  it("leaves the auto-assigned profile untouched when no profile fields are given", async () => {
    await onboardAgent({ privateKey: PK, sleep: noSleep });
    expect(updateAgentProfile).not.toHaveBeenCalled();
    expect(ipfsUpload).not.toHaveBeenCalled();
  });

  it("applies a chosen username + bio, and downstream URLs use the new handle", async () => {
    vi.mocked(updateAgentProfile).mockResolvedValue({
      username: "agent_smith",
    });
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      username: "agent_smith",
      bio: "I trade memecoins",
    });
    // No avatar → a single text-field call, and no avatarUri key.
    expect(updateAgentProfile).toHaveBeenCalledTimes(1);
    expect(updateAgentProfile).toHaveBeenCalledWith("tok", {
      username: "agent_smith",
      bio: "I trade memecoins",
    });
    expect(ipfsUpload).not.toHaveBeenCalled();
    expect(result.username).toBe("agent_smith");
    expect(result.profileUrl).toBe("https://zora.co/@agent_smith");
    expect(result.coin?.url).toBe("https://zora.co/@agent_smith/creator-coin");
  });

  it("uploads the avatar and forwards its URI to updateAgentProfile", async () => {
    vi.mocked(ipfsUpload).mockResolvedValue("ipfs://avatarcid");
    vi.mocked(updateAgentProfile).mockResolvedValue({
      username: "keen_cedar_9807",
      avatarUri: "ipfs://avatarcid",
    });
    const avatar = {
      filename: "me.png",
      bytes: new Uint8Array([1, 2, 3]),
      mimeType: "image/png",
    };
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      avatar,
    });
    expect(ipfsUpload).toHaveBeenCalledWith(
      "tok",
      "me.png",
      avatar.bytes,
      "image/png",
    );
    // Avatar only (no username/bio) → a single avatar-only call.
    expect(updateAgentProfile).toHaveBeenCalledTimes(1);
    expect(updateAgentProfile).toHaveBeenCalledWith("tok", {
      avatarUri: "ipfs://avatarcid",
    });
    expect(result.avatarUri).toBe("ipfs://avatarcid");
  });

  it("applies the username before uploading the avatar when both are set", async () => {
    vi.mocked(ipfsUpload).mockResolvedValue("ipfs://avatarcid");
    vi.mocked(updateAgentProfile)
      .mockResolvedValueOnce({ username: "agent_smith" })
      .mockResolvedValueOnce({
        username: "agent_smith",
        avatarUri: "ipfs://avatarcid",
      });
    const avatar = {
      filename: "me.png",
      bytes: new Uint8Array([1, 2, 3]),
      mimeType: "image/png",
    };
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      username: "agent_smith",
      avatar,
    });
    // The text fields go up first (validates the handle), then the avatar.
    expect(updateAgentProfile).toHaveBeenNthCalledWith(1, "tok", {
      username: "agent_smith",
      bio: undefined,
    });
    expect(ipfsUpload).toHaveBeenCalledWith(
      "tok",
      "me.png",
      avatar.bytes,
      "image/png",
    );
    expect(updateAgentProfile).toHaveBeenNthCalledWith(2, "tok", {
      avatarUri: "ipfs://avatarcid",
    });
    expect(result.username).toBe("agent_smith");
    expect(result.avatarUri).toBe("ipfs://avatarcid");
  });

  it("does not upload the avatar when the chosen username is unavailable", async () => {
    vi.mocked(updateAgentProfile).mockRejectedValue(
      new Error("username unavailable"),
    );
    const avatar = {
      filename: "me.png",
      bytes: new Uint8Array([1, 2, 3]),
      mimeType: "image/png",
    };
    await expect(
      onboardAgent({
        privateKey: PK,
        sleep: noSleep,
        username: "taken",
        avatar,
      }),
    ).rejects.toThrow(/username unavailable/);
    // The handle is validated first, so the slow upload never runs, and the
    // coin/post steps don't run either.
    expect(ipfsUpload).not.toHaveBeenCalled();
    expect(createCreatorCoin).not.toHaveBeenCalled();
    expect(createFirstPost).not.toHaveBeenCalled();
  });

  it("does not fabricate a post link on a dry run", async () => {
    vi.mocked(createFirstPost).mockResolvedValue({
      sponsored: true,
      simulation: "ExecutionResult",
      caption: "gm",
      ticker: "GM",
      imageUri: "ipfs://i",
      contractUri: "ipfs://c",
      // dry run: nothing minted, no coinAddress
    });
    const result = await onboardAgent({
      privateKey: PK,
      sleep: noSleep,
      dryRun: true,
      ...POST_ARGS,
    });
    expect(result.post?.url).toBeUndefined();
  });
});
