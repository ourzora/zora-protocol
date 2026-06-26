import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("../lib/hide.js", () => ({
  hideCoin: vi.fn(),
  unhideCoin: vi.fn(),
}));
vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  getApiKey: vi.fn(),
}));
vi.mock("../lib/privy-session.js", () => ({ ensurePrivySession: vi.fn() }));
vi.mock("../lib/wallet.js", () => ({
  normalizeKey: (k: string) => k,
}));
vi.mock("../lib/coin-ref.js", () => ({
  resolveCoin: vi.fn(),
  resolveAmbiguousName: vi.fn(),
}));
vi.mock("@zoralabs/coins-sdk", () => ({ setApiKey: vi.fn() }));
vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
  shutdownAnalytics: vi.fn(),
}));

import { hideCoin, unhideCoin } from "../lib/hide.js";
import { getPrivateKey, getApiKey } from "../lib/config.js";
import { ensurePrivySession } from "../lib/privy-session.js";
import { resolveCoin, resolveAmbiguousName } from "../lib/coin-ref.js";
import { track } from "../lib/analytics.js";
import { coinHideCommand, coinUnhideCommand } from "./hide.js";

const PK = `0x${"a".repeat(64)}`;
const COIN = "0x1fa82d2ccbf747e2be25339fde108bddbf9381b6";
const BASE = 8453;

function runHide(args: string[]) {
  return createProgram(coinHideCommand).parseAsync(["hide", ...args], {
    from: "user",
  });
}
function runUnhide(args: string[]) {
  return createProgram(coinUnhideCommand).parseAsync(["unhide", ...args], {
    from: "user",
  });
}

describe("coin hide / unhide commands", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let savedEnvKey: string | undefined;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    savedEnvKey = process.env.ZORA_PRIVATE_KEY;
    delete process.env.ZORA_PRIVATE_KEY;

    vi.mocked(getPrivateKey).mockReturnValue(PK);
    vi.mocked(getApiKey).mockReturnValue(undefined);
    vi.mocked(ensurePrivySession).mockResolvedValue({
      accessToken: "privy.jwt.token",
    } as Awaited<ReturnType<typeof ensurePrivySession>>);

    // Defaults: a name resolves to a known coin (creator/trend), and an address
    // resolves directly. Each test overrides as needed.
    vi.mocked(resolveAmbiguousName).mockResolvedValue({
      kind: "found",
      coin: { name: "Spam Coin", address: COIN },
    } as Awaited<ReturnType<typeof resolveAmbiguousName>>);
    vi.mocked(resolveCoin).mockResolvedValue({
      kind: "found",
      coin: { name: "Spam Coin", address: COIN },
    } as Awaited<ReturnType<typeof resolveCoin>>);

    vi.mocked(hideCoin).mockResolvedValue({ profileId: "me", handle: "me" });
    vi.mocked(unhideCoin).mockResolvedValue({ profileId: "me", handle: "me" });
  });

  afterEach(() => {
    if (savedEnvKey !== undefined) process.env.ZORA_PRIVATE_KEY = savedEnvKey;
    vi.restoreAllMocks();
    vi.clearAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  describe("hide", () => {
    it("hides a coin resolved by name (creator or trend) and outputs JSON", async () => {
      await runHide(["spam", "--json"]);
      expect(resolveAmbiguousName).toHaveBeenCalledWith("spam");
      expect(hideCoin).toHaveBeenCalledWith("privy.jwt.token", COIN, BASE);
      expect(parsedOutput()).toEqual({
        action: "hide",
        coin: COIN,
        hidden: true,
        profileId: "me",
      });
    });

    it("hides a raw address even when the indexer can't resolve it", async () => {
      vi.mocked(resolveCoin).mockResolvedValue({
        kind: "not-found",
        message: "No coin found",
      } as Awaited<ReturnType<typeof resolveCoin>>);
      await runHide([COIN]);
      // Addresses go through resolveCoin, not the name lookup.
      expect(resolveAmbiguousName).not.toHaveBeenCalled();
      expect(hideCoin).toHaveBeenCalledWith("privy.jwt.token", COIN, BASE);
    });

    it("forwards an explicit --chain to the mutation", async () => {
      await runHide(["spam", "--chain", "7777777"]);
      expect(hideCoin).toHaveBeenCalledWith("privy.jwt.token", COIN, 7777777);
    });

    it("rejects a non-numeric --chain", async () => {
      await expect(runHide(["spam", "--chain", "base"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --chain value"),
      );
      expect(hideCoin).not.toHaveBeenCalled();
    });

    it("errors for an unresolvable non-address identifier", async () => {
      vi.mocked(resolveAmbiguousName).mockResolvedValue({
        kind: "not-found",
        message: 'No coin found matching "ghost".',
      } as Awaited<ReturnType<typeof resolveAmbiguousName>>);
      await expect(runHide(["ghost"])).rejects.toThrow("process.exit(1)");
      expect(hideCoin).not.toHaveBeenCalled();
    });

    it("errors on a name that matches both a creator and a trend coin", async () => {
      vi.mocked(resolveAmbiguousName).mockResolvedValue({
        kind: "ambiguous",
        creator: { name: "C", address: COIN },
        trend: { name: "T", address: COIN },
      } as Awaited<ReturnType<typeof resolveAmbiguousName>>);
      await expect(runHide(["degen"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Multiple coins match"),
      );
      expect(hideCoin).not.toHaveBeenCalled();
    });

    it("renders a confirmation", async () => {
      await runHide(["spam"]);
      const out = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(out).toContain("✓ Hidden Spam Coin");
      expect(out).toContain(COIN);
    });

    it("records the coin and chain in the success analytics event", async () => {
      await runHide(["spam"]);
      expect(track).toHaveBeenCalledWith(
        "cli_hide",
        expect.objectContaining({
          action: "hide",
          success: true,
          coin: COIN,
          chain_id: BASE,
        }),
      );
    });

    it("errors when no identifier is given", async () => {
      await expect(runHide([])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Missing coin to hide"),
      );
      expect(hideCoin).not.toHaveBeenCalled();
    });

    it("errors with setup guidance when no wallet is configured", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(undefined);
      await expect(runHide(["spam"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("No wallet configured"),
      );
    });

    it("surfaces an API failure", async () => {
      vi.mocked(hideCoin).mockRejectedValue(
        new Error("addHiddenCreation failed: nope"),
      );
      await expect(runHide(["spam"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Failed to hide"),
      );
      expect(track).toHaveBeenCalledWith(
        "cli_hide",
        expect.objectContaining({ action: "hide", success: false }),
      );
    });
  });

  describe("unhide", () => {
    it("unhides a coin and outputs JSON", async () => {
      await runUnhide(["spam", "--json"]);
      expect(unhideCoin).toHaveBeenCalledWith("privy.jwt.token", COIN, BASE);
      expect(parsedOutput()).toEqual({
        action: "unhide",
        coin: COIN,
        hidden: false,
        profileId: "me",
      });
    });

    it("renders an unhidden confirmation", async () => {
      await runUnhide(["spam"]);
      const out = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(out).toContain("✓ Unhidden Spam Coin");
    });

    it("errors when sign-in fails", async () => {
      vi.mocked(ensurePrivySession).mockRejectedValue(
        new Error("SIWE rejected"),
      );
      await expect(runUnhide(["spam"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Sign-in failed"),
      );
      expect(unhideCoin).not.toHaveBeenCalled();
    });
  });
});
