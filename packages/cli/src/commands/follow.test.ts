import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("../lib/follow.js", () => ({
  followProfile: vi.fn(),
  unfollowProfile: vi.fn(),
}));
vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  getApiKey: vi.fn(),
}));
vi.mock("../lib/privy-session.js", () => ({ ensurePrivySession: vi.fn() }));
vi.mock("../lib/wallet.js", () => ({
  normalizeKey: (k: string) => k,
  resolveAccounts: vi.fn(),
  createClients: vi.fn(),
}));
vi.mock("@zoralabs/coins-sdk", () => ({
  getProfile: vi.fn(),
  setApiKey: vi.fn(),
}));
vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
  shutdownAnalytics: vi.fn(),
}));

import { followProfile, unfollowProfile } from "../lib/follow.js";
import { getPrivateKey, getApiKey } from "../lib/config.js";
import { ensurePrivySession } from "../lib/privy-session.js";
import { resolveAccounts, createClients } from "../lib/wallet.js";
import { getProfile } from "@zoralabs/coins-sdk";
import { track } from "../lib/analytics.js";
import { followCommand, unfollowCommand } from "./follow.js";

const PK = `0x${"a".repeat(64)}`;
const EOA = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";
const SMART_WALLET = "0x48Ba4a32D3418565BCEDb44e4C634021aCFCD117";
const CREATOR_COIN = "0x1111111111111111111111111111111111111111";

function runFollow(args: string[]) {
  const program = createProgram(followCommand);
  return program.parseAsync(["follow", ...args], { from: "user" });
}

function runUnfollow(args: string[]) {
  const program = createProgram(unfollowCommand);
  return program.parseAsync(["unfollow", ...args], { from: "user" });
}

describe("follow / unfollow commands", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let savedEnvKey: string | undefined;
  const publicClient = { readContract: vi.fn() };

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    // The command reads ZORA_PRIVATE_KEY before getPrivateKey(); clear it so the
    // mocked getPrivateKey is the single source of truth in tests.
    savedEnvKey = process.env.ZORA_PRIVATE_KEY;
    delete process.env.ZORA_PRIVATE_KEY;

    vi.mocked(getPrivateKey).mockReturnValue(PK);
    vi.mocked(getApiKey).mockReturnValue(undefined);
    vi.mocked(ensurePrivySession).mockResolvedValue({
      accessToken: "privy.jwt.token",
    } as Awaited<ReturnType<typeof ensurePrivySession>>);

    // Follow gate defaults: target has a creator coin and the viewer holds it.
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: { handle: "creator", creatorCoin: { address: CREATOR_COIN } },
      },
    } as any);
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA },
      smartWalletAccount: { address: SMART_WALLET },
    } as unknown as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
    } as unknown as ReturnType<typeof createClients>);
    publicClient.readContract.mockResolvedValue(5n);

    vi.mocked(followProfile).mockResolvedValue({
      handle: "wbnns",
      profileId: "wbnns",
      followingStatus: "FOLLOWING",
    });
    vi.mocked(unfollowProfile).mockResolvedValue({
      handle: "wbnns",
      profileId: "wbnns",
      followingStatus: "NOT_FOLLOWING",
    });
  });

  afterEach(() => {
    if (savedEnvKey !== undefined) process.env.ZORA_PRIVATE_KEY = savedEnvKey;
    vi.restoreAllMocks();
    vi.clearAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  describe("follow", () => {
    it("follows a user (whose creator coin is held) and outputs JSON", async () => {
      await runFollow(["wbnns", "--json"]);
      expect(followProfile).toHaveBeenCalledWith("privy.jwt.token", "wbnns");
      expect(parsedOutput()).toEqual({
        action: "follow",
        followee: "wbnns",
        handle: "wbnns",
        followingStatus: "FOLLOWING",
        profileUrl: "https://zora.co/@wbnns",
      });
    });

    it("checks the creator-coin balance of the smart wallet", async () => {
      await runFollow(["wbnns"]);
      expect(publicClient.readContract).toHaveBeenCalledWith(
        expect.objectContaining({
          address: CREATOR_COIN,
          functionName: "balanceOf",
          args: [SMART_WALLET],
        }),
      );
    });

    it("strips a leading @ from the identifier", async () => {
      await runFollow(["@wbnns"]);
      expect(followProfile).toHaveBeenCalledWith("privy.jwt.token", "wbnns");
    });

    it("renders a confirmation with the profile URL", async () => {
      await runFollow(["wbnns"]);
      const out = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(out).toContain("✓ Following @wbnns");
      expect(out).toContain("https://zora.co/@wbnns");
    });

    it("notes a mutual follow", async () => {
      vi.mocked(followProfile).mockResolvedValue({
        handle: "wbnns",
        profileId: "wbnns",
        followingStatus: "MUTUAL_FOLLOWING",
      });
      await runFollow(["wbnns"]);
      const out = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(out).toContain("You follow each other.");
    });

    // --- creator-coin gate ---

    it("blocks the follow when the viewer holds none of the creator coin", async () => {
      publicClient.readContract.mockResolvedValue(0n);
      await expect(runFollow(["creator"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("must hold @creator's creator coin"),
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining(`zora buy ${CREATOR_COIN}`),
      );
      expect(followProfile).not.toHaveBeenCalled();
    });

    it("blocks the follow when the target has no creator coin", async () => {
      vi.mocked(getProfile).mockResolvedValue({
        data: { profile: { handle: "nocoin", creatorCoin: null } },
      } as any);
      await expect(runFollow(["nocoin"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("doesn't have a creator coin"),
      );
      expect(followProfile).not.toHaveBeenCalled();
    });

    it("blocks the follow when the profile can't be found", async () => {
      vi.mocked(getProfile).mockResolvedValue({
        data: { profile: null },
      } as any);
      await expect(runFollow(["ghost"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining('No Zora profile found for "ghost"'),
      );
      expect(followProfile).not.toHaveBeenCalled();
    });

    it("errors when no identifier is given", async () => {
      await expect(runFollow([])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Missing user to follow"),
      );
      expect(followProfile).not.toHaveBeenCalled();
    });

    it("errors with setup guidance when no wallet is configured", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(undefined);
      await expect(runFollow(["wbnns"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("No wallet configured"),
      );
    });

    it("rejects following yourself when the API resolves to your own profile", async () => {
      vi.mocked(followProfile).mockResolvedValue({
        handle: "me",
        profileId: "me",
        followingStatus: "SELF",
      });
      await expect(runFollow(["me"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("can't follow yourself"),
      );
      // The SELF no-op still records an analytics event (not silently dropped).
      expect(track).toHaveBeenCalledWith(
        "cli_follow",
        expect.objectContaining({
          action: "follow",
          success: false,
          error_type: "self",
        }),
      );
    });

    it("maps a 'yourself' API error to friendly guidance", async () => {
      vi.mocked(followProfile).mockRejectedValue(
        new Error("follow failed: You cannot follow yourself."),
      );
      await expect(runFollow(["me"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("can't follow yourself"),
      );
      expect(track).toHaveBeenCalledWith(
        "cli_follow",
        expect.objectContaining({ action: "follow", success: false }),
      );
    });

    it("surfaces a generic API failure", async () => {
      vi.mocked(followProfile).mockRejectedValue(
        new Error("follow failed: Profile not found."),
      );
      await expect(runFollow(["ghost"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining('Failed to follow "ghost"'),
      );
    });
  });

  describe("unfollow", () => {
    it("unfollows a user and outputs JSON", async () => {
      await runUnfollow(["wbnns", "--json"]);
      expect(unfollowProfile).toHaveBeenCalledWith("privy.jwt.token", "wbnns");
      expect(parsedOutput()).toEqual({
        action: "unfollow",
        followee: "wbnns",
        handle: "wbnns",
        followingStatus: "NOT_FOLLOWING",
        profileUrl: "https://zora.co/@wbnns",
      });
    });

    it("does NOT apply the creator-coin gate", async () => {
      // Even with a zero balance, unfollowing always proceeds.
      publicClient.readContract.mockResolvedValue(0n);
      await runUnfollow(["wbnns"]);
      expect(getProfile).not.toHaveBeenCalled();
      expect(unfollowProfile).toHaveBeenCalledWith("privy.jwt.token", "wbnns");
    });

    it("renders an unfollowed confirmation", async () => {
      await runUnfollow(["wbnns"]);
      const out = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(out).toContain("✓ Unfollowed @wbnns");
    });

    it("notes when the other user still follows you", async () => {
      vi.mocked(unfollowProfile).mockResolvedValue({
        handle: "wbnns",
        profileId: "wbnns",
        followingStatus: "FOLLOWED",
      });
      await runUnfollow(["wbnns"]);
      const out = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(out).toContain("They still follow you.");
    });

    // Independent coverage of the shared error paths for the unfollow action
    // (message wording interpolates the action, e.g. "unfollow").

    it("errors when no identifier is given", async () => {
      await expect(runUnfollow([])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Missing user to unfollow"),
      );
      expect(unfollowProfile).not.toHaveBeenCalled();
    });

    it("surfaces a generic API failure", async () => {
      vi.mocked(unfollowProfile).mockRejectedValue(
        new Error("unfollow failed: Profile not found."),
      );
      await expect(runUnfollow(["ghost"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining('Failed to unfollow "ghost"'),
      );
    });

    it("errors when sign-in fails", async () => {
      // unfollow has no creator-coin gate, so this isolates resolveToken's
      // catch branch (ensurePrivySession rejecting).
      vi.mocked(ensurePrivySession).mockRejectedValue(
        new Error("SIWE rejected"),
      );
      await expect(runUnfollow(["wbnns"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Sign-in failed"),
      );
      expect(unfollowProfile).not.toHaveBeenCalled();
    });
  });
});
