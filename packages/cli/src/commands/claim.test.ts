import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Address, type PrivateKeyAccount } from "viem";
import { createProgram } from "../test/create-program.js";

vi.mock("@inquirer/confirm");
vi.mock("../lib/config.js", () => ({ getApiKey: vi.fn() }));
vi.mock("../lib/wallet.js");
vi.mock("@zoralabs/coins-sdk", () => ({
  getProfile: vi.fn(),
  setApiKey: vi.fn(),
  prepareUserOperation: vi.fn(),
  submitUserOperation: vi.fn(),
  toGenericCall: vi.fn((call) => call),
  toUserOperationCalls: vi.fn((calls) => calls),
  // gas.ts does `error instanceof CoinbaseGasError`; needs to be a constructor.
  CoinbaseGasError: class CoinbaseGasError extends Error {},
}));
vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
  shutdownAnalytics: vi.fn(),
}));

import confirm from "@inquirer/confirm";
import {
  getProfile,
  prepareUserOperation,
  setApiKey,
  submitUserOperation,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";
import { track } from "../lib/analytics.js";
import { claimCommand } from "./claim.js";

const EOA = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const SMART_WALLET = "0x48Ba4a32D3418565BCEDb44e4C634021aCFCD117" as Address;
const CREATOR_COIN = "0x1111111111111111111111111111111111111111" as Address;
const OTHER_COIN = "0x2222222222222222222222222222222222222222" as Address;
const TX_HASH = `0x${"a".repeat(64)}`;

function runClaim(args: string[]) {
  const program = createProgram(claimCommand);
  return program.parseAsync(["claim", ...args], { from: "user" });
}

describe("claim command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;

  const publicClient = {
    readContract: vi.fn(),
    waitForTransactionReceipt: vi.fn(),
  };
  const walletClient = { writeContract: vi.fn() };

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    vi.mocked(getApiKey).mockReturnValue(undefined);
    vi.mocked(confirm).mockResolvedValue(true);
    vi.mocked(getProfile).mockResolvedValue({
      data: { profile: { creatorCoin: { address: CREATOR_COIN } } },
    } as any);
    // EOA wallet by default.
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA, type: "local" } as PrivateKeyAccount,
      smartWalletAccount: undefined,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
    } as unknown as ReturnType<typeof createClients>);

    publicClient.readContract.mockResolvedValue(1_000_000_000_000_000_000n); // 1.0
    publicClient.waitForTransactionReceipt.mockResolvedValue({});
    walletClient.writeContract.mockResolvedValue(TX_HASH);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.clearAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  it("resolves the wallet's own creator coin, reads claimable, and claims via EOA", async () => {
    await runClaim(["--yes"]);

    expect(getProfile).toHaveBeenCalledWith({ identifier: EOA });
    expect(publicClient.readContract).toHaveBeenCalledWith(
      expect.objectContaining({
        address: CREATOR_COIN,
        functionName: "getClaimableAmount",
      }),
    );
    expect(walletClient.writeContract).toHaveBeenCalledWith(
      expect.objectContaining({
        address: CREATOR_COIN,
        functionName: "claimVesting",
      }),
    );
    expect(publicClient.waitForTransactionReceipt).toHaveBeenCalledWith({
      hash: TX_HASH,
    });
  });

  it("uses --coin without a profile lookup", async () => {
    await runClaim(["--coin", OTHER_COIN, "--yes"]);

    expect(getProfile).not.toHaveBeenCalled();
    expect(walletClient.writeContract).toHaveBeenCalledWith(
      expect.objectContaining({ address: OTHER_COIN }),
    );
  });

  it("rejects an invalid --coin address", async () => {
    await expect(runClaim(["--coin", "nope", "--yes"])).rejects.toThrow();
    expect(walletClient.writeContract).not.toHaveBeenCalled();
  });

  it("skips the transaction when there is nothing to claim", async () => {
    publicClient.readContract.mockResolvedValue(0n);

    await runClaim(["--json"]);

    expect(walletClient.writeContract).not.toHaveBeenCalled();
    expect(parsedOutput()).toEqual({
      action: "claim",
      coin: CREATOR_COIN,
      claimable: "0",
      claimed: false,
    });
    expect(track).toHaveBeenCalledWith(
      "cli_claim",
      expect.objectContaining({ action: "nothing_to_claim" }),
    );
  });

  it("errors when the wallet has no creator coin", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: { profile: { creatorCoin: null } },
    } as any);

    await expect(runClaim(["--yes"])).rejects.toThrow();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("No creator coin found"),
    );
  });

  it("outputs JSON on a successful claim", async () => {
    await runClaim(["--json", "--yes"]);

    expect(parsedOutput()).toEqual({
      action: "claim",
      coin: CREATOR_COIN,
      claimed: { amount: "1", raw: "1000000000000000000" },
      tx: TX_HASH,
    });
  });

  it("claims through the smart wallet bundler when present", async () => {
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA, type: "local" } as PrivateKeyAccount,
      smartWalletAccount: { address: SMART_WALLET, type: "smart" },
    } as unknown as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
      bundlerClient: {},
    } as unknown as ReturnType<typeof createClients>);
    vi.mocked(prepareUserOperation).mockResolvedValue({} as any);
    vi.mocked(submitUserOperation).mockResolvedValue({
      success: true,
      receipt: { transactionHash: TX_HASH },
    } as any);

    await runClaim(["--yes"]);

    expect(getProfile).toHaveBeenCalledWith({ identifier: SMART_WALLET });
    expect(submitUserOperation).toHaveBeenCalled();
    expect(walletClient.writeContract).not.toHaveBeenCalled();
  });

  it("errors when a smart wallet has no bundler client", async () => {
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA, type: "local" } as PrivateKeyAccount,
      smartWalletAccount: { address: SMART_WALLET, type: "smart" },
    } as unknown as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
    } as unknown as ReturnType<typeof createClients>);

    await expect(runClaim(["--yes"])).rejects.toThrow();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("bundler client"),
    );
    expect(getProfile).not.toHaveBeenCalled();
  });

  it("errors when the profile lookup fails", async () => {
    vi.mocked(getProfile).mockRejectedValue(new Error("network down"));

    await expect(runClaim(["--yes"])).rejects.toThrow();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Failed to look up your creator coin"),
    );
  });

  it("errors when reading the claimable amount fails", async () => {
    publicClient.readContract.mockRejectedValue(new Error("rpc error"));

    await expect(runClaim(["--coin", OTHER_COIN, "--yes"])).rejects.toThrow();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Failed to read claimable rewards"),
    );
  });

  it("aborts without sending when the confirmation is declined", async () => {
    vi.mocked(confirm).mockResolvedValue(false);

    await expect(runClaim([])).rejects.toThrow();
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
    expect(walletClient.writeContract).not.toHaveBeenCalled();
  });

  it("surfaces a clear error when the claim transaction fails", async () => {
    walletClient.writeContract.mockRejectedValue(new Error("insufficient gas"));

    await expect(runClaim(["--yes"])).rejects.toThrow();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Claim failed"),
    );
    expect(track).toHaveBeenCalledWith(
      "cli_claim",
      expect.objectContaining({ success: false }),
    );
  });

  it("errors when the smart wallet user operation reverts", async () => {
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA, type: "local" } as PrivateKeyAccount,
      smartWalletAccount: { address: SMART_WALLET, type: "smart" },
    } as unknown as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
      bundlerClient: {},
    } as unknown as ReturnType<typeof createClients>);
    vi.mocked(prepareUserOperation).mockResolvedValue({} as any);
    vi.mocked(submitUserOperation).mockResolvedValue({
      success: false,
      reason: "AA21 didn't pay prefund",
    } as any);

    await expect(runClaim(["--yes"])).rejects.toThrow();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Claim failed"),
    );
  });

  it("applies the configured API key", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-api-key");

    await runClaim(["--yes"]);

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
  });

  it("prints a friendly message (non-JSON) when there is nothing to claim", async () => {
    publicClient.readContract.mockResolvedValue(0n);

    await runClaim([]);

    expect(logSpy.mock.calls.map((c) => c[0]).join("\n")).toContain(
      "Nothing to claim",
    );
    expect(walletClient.writeContract).not.toHaveBeenCalled();
  });
});
