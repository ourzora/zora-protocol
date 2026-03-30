import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Address, getAddress, parseEther } from "viem";
import { createProgram } from "../test/create-program.js";

vi.mock("@inquirer/confirm");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));
vi.mock("../lib/wallet.js");

vi.mock("@zoralabs/coins-sdk");
vi.mock("../lib/analytics.js");
vi.mock("../lib/wallet-balances.js");

import confirm from "@inquirer/confirm";
import { setApiKey, getCoin, getProfile, getTrend } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { createClients, resolveAccount } from "../lib/wallet.js";
import { track } from "../lib/analytics.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";
import { sendCommand } from "./send.js";

const COIN_ADDRESS = "0x1234567890abcdef1234567890abcdef12345678" as Address;
const ACCOUNT_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const RECIPIENT_ADDRESS = getAddress(
  "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01",
);
const TX_HASH =
  "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

function runSend(args: string[]) {
  const program = createProgram(sendCommand);
  return program.parseAsync(["send", ...args], { from: "user" });
}

function runSendJson(args: string[]) {
  const program = createProgram(sendCommand);
  return program.parseAsync(["send", ...args, "--json"], { from: "user" });
}

describe("send command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  const publicClient = {
    getBalance: vi.fn(),
    readContract: vi.fn(),
    waitForTransactionReceipt: vi.fn(),
  };

  const walletClient = {
    sendTransaction: vi.fn(),
    writeContract: vi.fn(),
  };

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getTrend).mockResolvedValue({
      data: { trendCoin: null },
    } as any);
    vi.mocked(resolveAccount).mockReturnValue({
      address: ACCOUNT_ADDRESS,
    } as ReturnType<typeof resolveAccount>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
    } as unknown as ReturnType<typeof createClients>);
    vi.mocked(confirm).mockResolvedValue(true);
    vi.mocked(fetchTokenPriceUsd).mockResolvedValue(2500);

    publicClient.getBalance.mockResolvedValue(parseEther("1.0"));
    publicClient.waitForTransactionReceipt.mockResolvedValue({});
    walletClient.sendTransaction.mockResolvedValue(TX_HASH);
    walletClient.writeContract.mockResolvedValue(TX_HASH);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function parsedOutput(): unknown {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  // --- Validation ---

  describe("validation", () => {
    it("exits with error when --to is missing", async () => {
      await expect(runSend(["eth", "--amount", "0.1"])).rejects.toThrow();
    });

    it("exits with error when --to is not a valid address", async () => {
      await expect(
        runSend(["eth", "--to", "not-an-address", "--amount", "0.1"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid recipient address"),
      );
    });

    it("exits with error when no amount flag is provided", async () => {
      await expect(runSend(["eth", "--to", RECIPIENT_ADDRESS])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Specify one amount flag"),
      );
    });

    it("exits with error when multiple amount flags are provided", async () => {
      await expect(
        runSend(["eth", "--to", RECIPIENT_ADDRESS, "--amount", "0.1", "--all"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Only one amount flag"),
      );
    });
  });

  // --- ETH send ---

  describe("ETH send", () => {
    it("sends ETH with --amount", async () => {
      await runSend([
        "eth",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      expect(walletClient.sendTransaction).toHaveBeenCalledWith({
        to: RECIPIENT_ADDRESS,
        value: parseEther("0.5"),
      });
      expect(publicClient.waitForTransactionReceipt).toHaveBeenCalledWith({
        hash: TX_HASH,
      });
    });

    it("sends ETH with --all (subtracts gas reserve)", async () => {
      publicClient.getBalance.mockResolvedValue(parseEther("1.0"));

      await runSend(["eth", "--to", RECIPIENT_ADDRESS, "--all", "--yes"]);

      // 1.0 - 0.00001 gas reserve = 0.99999
      expect(walletClient.sendTransaction).toHaveBeenCalledWith({
        to: RECIPIENT_ADDRESS,
        value: parseEther("0.99999"),
      });
    });

    it("sends ETH with --percent", async () => {
      publicClient.getBalance.mockResolvedValue(parseEther("2.0"));

      await runSend([
        "eth",
        "--to",
        RECIPIENT_ADDRESS,
        "--percent",
        "50",
        "--yes",
      ]);

      // spendable = 2.0 - 0.00001 = 1.99999, 50% = 0.999995
      const expectedAmount =
        ((parseEther("2.0") - parseEther("0.00001")) * 5000n) / 10000n;
      expect(walletClient.sendTransaction).toHaveBeenCalledWith({
        to: RECIPIENT_ADDRESS,
        value: expectedAmount,
      });
    });

    it("exits with error when ETH balance is zero", async () => {
      publicClient.getBalance.mockResolvedValue(0n);

      await expect(
        runSend(["eth", "--to", RECIPIENT_ADDRESS, "--amount", "0.1", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("No ETH balance"),
      );
    });

    it("exits with error when --all but balance <= gas reserve", async () => {
      publicClient.getBalance.mockResolvedValue(parseEther("0.000005"));

      await expect(
        runSend(["eth", "--to", RECIPIENT_ADDRESS, "--all", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Balance too low"),
      );
    });

    it("exits with error when --amount exceeds balance including gas", async () => {
      publicClient.getBalance.mockResolvedValue(parseEther("0.5"));

      await expect(
        runSend(["eth", "--to", RECIPIENT_ADDRESS, "--amount", "0.5", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Insufficient balance"),
      );
    });

    it("outputs JSON for ETH send", async () => {
      await runSendJson([
        "eth",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.1",
        "--yes",
      ]);

      const output = parsedOutput() as Record<string, unknown>;
      expect(output).toMatchObject({
        action: "send",
        coin: "ETH",
        address: null,
        to: RECIPIENT_ADDRESS,
        tx: TX_HASH,
      });
      const sent = output.sent as Record<string, unknown>;
      expect(sent).toHaveProperty("amountUsd");
      expect(sent.amountUsd).toBe(250);
    });

    it("prints table output for ETH send", async () => {
      await runSend([
        "eth",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.1",
        "--yes",
      ]);

      const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(output).toContain("Sent ETH");
      expect(output).toContain(RECIPIENT_ADDRESS);
      expect(output).toContain(TX_HASH);
    });

    it("tracks analytics on successful ETH send", async () => {
      await runSend([
        "eth",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.1",
        "--yes",
      ]);

      expect(track).toHaveBeenCalledWith(
        "cli_send",
        expect.objectContaining({
          asset: "eth",
          amount_usd: 250,
          success: true,
          tx_hash: TX_HASH,
        }),
      );
    });

    it("tracks analytics on failed ETH send", async () => {
      walletClient.sendTransaction.mockRejectedValue(
        new Error("insufficient funds"),
      );

      await expect(
        runSend(["eth", "--to", RECIPIENT_ADDRESS, "--amount", "0.1", "--yes"]),
      ).rejects.toThrow("process.exit(1)");

      expect(track).toHaveBeenCalledWith(
        "cli_send",
        expect.objectContaining({
          asset: "eth",
          success: false,
        }),
      );
    });
  });

  // --- Confirmation ---

  describe("confirmation", () => {
    it("prompts for confirmation by default", async () => {
      await runSend(["eth", "--to", RECIPIENT_ADDRESS, "--amount", "0.1"]);

      expect(confirm).toHaveBeenCalledWith({
        message: "Confirm?",
        default: false,
      });
    });

    it("skips confirmation with --yes", async () => {
      await runSend([
        "eth",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.1",
        "--yes",
      ]);

      expect(confirm).not.toHaveBeenCalled();
    });

    it("aborts when user declines confirmation", async () => {
      vi.mocked(confirm).mockResolvedValue(false);

      await expect(
        runSend(["eth", "--to", RECIPIENT_ADDRESS, "--amount", "0.1"]),
      ).rejects.toThrow("process.exit(0)");
      expect(errorSpy).toHaveBeenCalledWith("Aborted.");
    });
  });

  // --- Coin (ERC-20) send ---

  describe("coin send", () => {
    beforeEach(() => {
      vi.mocked(getCoin).mockResolvedValue({
        data: {
          zora20Token: {
            name: "Test Coin",
            address: COIN_ADDRESS,
            coinType: "CREATOR",
            marketCap: "5000000",
          },
        },
      } as any);

      // readContract returns different values depending on functionName
      publicClient.readContract.mockImplementation(
        ({ functionName }: { functionName: string }) => {
          if (functionName === "balanceOf") return 1000000000000000000n; // 1 token
          if (functionName === "decimals") return 18;
          if (functionName === "symbol") return "TEST";
          return 0n;
        },
      );
    });

    it("sends coin by address with --amount", async () => {
      await runSend([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      expect(walletClient.writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          address: COIN_ADDRESS,
          functionName: "transfer",
          args: [RECIPIENT_ADDRESS, parseEther("0.5")],
        }),
      );
      expect(publicClient.waitForTransactionReceipt).toHaveBeenCalledWith({
        hash: TX_HASH,
      });
    });

    it("sends coin with --all (full balance)", async () => {
      await runSend([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--all",
        "--yes",
      ]);

      expect(walletClient.writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          functionName: "transfer",
          args: [RECIPIENT_ADDRESS, 1000000000000000000n],
        }),
      );
    });

    it("sends coin with --percent", async () => {
      await runSend([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--percent",
        "25",
        "--yes",
      ]);

      const expectedAmount = (1000000000000000000n * 2500n) / 10000n;
      expect(walletClient.writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          functionName: "transfer",
          args: [RECIPIENT_ADDRESS, expectedAmount],
        }),
      );
    });

    it("resolves coin by creator name with type prefix", async () => {
      vi.mocked(getProfile).mockResolvedValue({
        data: {
          profile: {
            handle: "jacob",
            creatorCoin: { address: COIN_ADDRESS },
          },
        },
      } as any);

      await runSend([
        "creator-coin",
        "jacob",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      expect(getProfile).toHaveBeenCalledWith({ identifier: "jacob" });
      expect(walletClient.writeContract).toHaveBeenCalled();
    });

    it("exits with error when coin not found", async () => {
      vi.mocked(getCoin).mockResolvedValue({
        data: { zora20Token: null },
      } as any);

      await expect(
        runSend([
          COIN_ADDRESS,
          "--to",
          RECIPIENT_ADDRESS,
          "--amount",
          "1",
          "--yes",
        ]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("No coin found"),
      );
    });

    it("exits with error when balance is zero", async () => {
      publicClient.readContract.mockImplementation(
        ({ functionName }: { functionName: string }) => {
          if (functionName === "balanceOf") return 0n;
          if (functionName === "decimals") return 18;
          if (functionName === "symbol") return "TEST";
          return 0n;
        },
      );

      await expect(
        runSend([
          COIN_ADDRESS,
          "--to",
          RECIPIENT_ADDRESS,
          "--amount",
          "1",
          "--yes",
        ]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("No TEST balance"),
      );
    });

    it("exits with error when --amount exceeds balance", async () => {
      await expect(
        runSend([
          COIN_ADDRESS,
          "--to",
          RECIPIENT_ADDRESS,
          "--amount",
          "5",
          "--yes",
        ]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Insufficient balance"),
      );
    });

    it("exits with error when transaction fails", async () => {
      walletClient.writeContract.mockRejectedValue(
        new Error("execution reverted"),
      );

      await expect(
        runSend([
          COIN_ADDRESS,
          "--to",
          RECIPIENT_ADDRESS,
          "--amount",
          "0.5",
          "--yes",
        ]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Transaction failed"),
      );
    });

    it("outputs JSON for coin send", async () => {
      await runSendJson([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      const output = parsedOutput() as Record<string, unknown>;
      expect(output).toMatchObject({
        action: "send",
        coin: "TEST",
        address: COIN_ADDRESS,
        to: RECIPIENT_ADDRESS,
        tx: TX_HASH,
      });
    });

    it("prints table output for coin send", async () => {
      await runSend([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(output).toContain("Sent Test Coin");
      expect(output).toContain("TEST");
      expect(output).toContain(RECIPIENT_ADDRESS);
      expect(output).toContain(TX_HASH);
    });

    it("sets API key when configured", async () => {
      await runSend([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    });

    it("does not set API key when not configured", async () => {
      vi.mocked(getApiKey).mockReturnValue(undefined);

      await runSend([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      expect(setApiKey).not.toHaveBeenCalled();
    });

    it("tracks analytics on successful coin send", async () => {
      await runSend([
        COIN_ADDRESS,
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "0.5",
        "--yes",
      ]);

      expect(track).toHaveBeenCalledWith(
        "cli_send",
        expect.objectContaining({
          asset: "coin",
          coin_address: COIN_ADDRESS,
          coin_symbol: "TEST",
          amount_usd: expect.any(Number),
          success: true,
          tx_hash: TX_HASH,
        }),
      );
    });

    it("tracks analytics on failed coin send", async () => {
      walletClient.writeContract.mockRejectedValue(new Error("reverted"));

      await expect(
        runSend([
          COIN_ADDRESS,
          "--to",
          RECIPIENT_ADDRESS,
          "--amount",
          "0.5",
          "--yes",
        ]),
      ).rejects.toThrow("process.exit(1)");

      expect(track).toHaveBeenCalledWith(
        "cli_send",
        expect.objectContaining({
          asset: "coin",
          success: false,
        }),
      );
    });
  });

  // --- Known tokens (usdc, zora) ---

  describe("known token send", () => {
    beforeEach(() => {
      publicClient.readContract.mockImplementation(
        ({ functionName }: { functionName: string }) => {
          if (functionName === "balanceOf") return 50000000n; // 50 USDC (6 decimals)
          return 0n;
        },
      );
    });

    it("sends USDC by name without coin resolution", async () => {
      await runSend([
        "usdc",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "10",
        "--yes",
      ]);

      expect(getCoin).not.toHaveBeenCalled();
      expect(walletClient.writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          functionName: "transfer",
          args: [RECIPIENT_ADDRESS, 10000000n], // 10 USDC = 10 * 10^6
        }),
      );
    });

    it("sends ZORA by name without coin resolution", async () => {
      publicClient.readContract.mockImplementation(
        ({ functionName }: { functionName: string }) => {
          if (functionName === "balanceOf") return parseEther("100");
          return 0n;
        },
      );

      await runSend([
        "zora",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "5",
        "--yes",
      ]);

      expect(getCoin).not.toHaveBeenCalled();
      expect(walletClient.writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          functionName: "transfer",
          args: [RECIPIENT_ADDRESS, parseEther("5")],
        }),
      );
    });

    it("sends all USDC with --all", async () => {
      await runSend(["usdc", "--to", RECIPIENT_ADDRESS, "--all", "--yes"]);

      expect(walletClient.writeContract).toHaveBeenCalledWith(
        expect.objectContaining({
          functionName: "transfer",
          args: [RECIPIENT_ADDRESS, 50000000n],
        }),
      );
    });

    it("is case-insensitive for known tokens", async () => {
      await runSend([
        "USDC",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "10",
        "--yes",
      ]);

      expect(getCoin).not.toHaveBeenCalled();
      expect(walletClient.writeContract).toHaveBeenCalled();
    });

    it("outputs JSON for known token send", async () => {
      await runSendJson([
        "usdc",
        "--to",
        RECIPIENT_ADDRESS,
        "--amount",
        "10",
        "--yes",
      ]);

      const output = parsedOutput() as Record<string, unknown>;
      expect(output).toMatchObject({
        action: "send",
        coin: "USDC",
        to: RECIPIENT_ADDRESS,
        tx: TX_HASH,
      });
    });

    it("exits with error when known token balance is zero", async () => {
      publicClient.readContract.mockImplementation(() => 0n);

      await expect(
        runSend(["usdc", "--to", RECIPIENT_ADDRESS, "--amount", "10", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("No USDC balance"),
      );
    });
  });
});
