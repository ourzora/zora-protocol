import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  encodeAbiParameters,
  encodeEventTopics,
  erc20Abi,
  type Address,
} from "viem";

vi.mock("@inquirer/confirm", () => ({ default: vi.fn() }));

vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));

vi.mock("../lib/wallet.js", () => ({
  resolveAccount: vi.fn(),
  createClients: vi.fn(),
}));

vi.mock("@zoralabs/coins-sdk");

vi.mock("../lib/wallet-balances.js", () => ({
  fetchTokenPriceUsd: vi.fn(),
}));

vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
  shutdownAnalytics: vi.fn().mockResolvedValue(undefined),
}));

import confirm from "@inquirer/confirm";
import {
  createTradeCall,
  getCoin,
  setApiKey,
  tradeCoin,
} from "@zoralabs/coins-sdk";
import { track } from "../lib/analytics.js";
import { getApiKey } from "../lib/config.js";
import { createClients, resolveAccount } from "../lib/wallet.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";
import { buyCommand } from "./buy.js";
import { createProgram } from "../test/create-program.js";

const COIN_ADDRESS = "0x1234567890abcdef1234567890abcdef12345678" as Address;
const ACCOUNT_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const RECEIPT_TRANSFER_AMOUNT = 1500000000000000000n;

function makeTransferLog({
  tokenAddress,
  from,
  to,
  value,
}: {
  tokenAddress: Address;
  from: Address;
  to: Address;
  value: bigint;
}) {
  return {
    address: tokenAddress,
    topics: encodeEventTopics({
      abi: erc20Abi,
      eventName: "Transfer",
      args: { from, to },
    }),
    data: encodeAbiParameters([{ type: "uint256" }], [value]),
  };
}

function runBuy(args: string[]) {
  const program = createProgram(buyCommand);
  return program.parseAsync(["buy", ...args], { from: "user" });
}

describe("buy command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  const publicClient = {
    getBalance: vi.fn(),
    readContract: vi.fn(),
  };

  const walletClient = {};

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(resolveAccount).mockReturnValue({
      address: ACCOUNT_ADDRESS,
    } as ReturnType<typeof resolveAccount>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
    } as ReturnType<typeof createClients>);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "Test Coin",
          symbol: "TEST",
        },
      },
    } as Awaited<ReturnType<typeof getCoin>>);
    vi.mocked(createTradeCall).mockResolvedValue({
      quote: {
        amountOut: "2000000000000000000",
      },
    } as Awaited<ReturnType<typeof createTradeCall>>);
    vi.mocked(tradeCoin).mockResolvedValue({
      transactionHash:
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      logs: [
        makeTransferLog({
          tokenAddress: COIN_ADDRESS,
          from: "0x000000000000000000000000000000000000dead",
          to: ACCOUNT_ADDRESS,
          value: RECEIPT_TRANSFER_AMOUNT,
        }),
      ],
    } as Awaited<ReturnType<typeof tradeCoin>>);
    vi.mocked(confirm).mockResolvedValue(true);
    vi.mocked(fetchTokenPriceUsd).mockResolvedValue(2500);
    publicClient.getBalance.mockResolvedValue(0n);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("only exposes supported amount flags", async () => {
    const optionNames = buyCommand.options.map((option) => option.long);

    expect(optionNames).toContain("--eth");
    expect(optionNames).toContain("--usd");
    expect(optionNames).toContain("--token");
    expect(optionNames).toContain("--debug");
    expect(optionNames).toContain("--percent");
    expect(optionNames).toContain("--all");
    expect(optionNames).not.toContain("--amount");
  });

  it("exits when no amount flag is provided", async () => {
    await expect(runBuy([COIN_ADDRESS])).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "Specify one amount flag: --eth, --usd, --percent, or --all",
      ),
    );
  });

  it("exits when multiple amount flags are provided", async () => {
    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--percent", "25"]),
    ).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Only one amount flag allowed"),
    );
  });

  it("rejects removed unsupported flags as unknown options", async () => {
    const stderrSpy = vi
      .spyOn(process.stderr, "write")
      .mockImplementation(() => true);

    await expect(
      runBuy([COIN_ADDRESS, "--from", "something"]),
    ).rejects.toThrow();

    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("unknown option '--from'"),
    );

    stderrSpy.mockRestore();
  });

  it("executes an ETH buy and prints JSON output", async () => {
    await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--json"]);

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(createTradeCall).toHaveBeenCalledWith(
      expect.objectContaining({
        amountIn: 100000000000000000n,
        slippage: 0.01,
        sender: ACCOUNT_ADDRESS,
      }),
    );
    expect(tradeCoin).toHaveBeenCalled();
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining('"action": "buy"'),
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining('"amount": "1.5"'),
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(`"raw": "${RECEIPT_TRANSFER_AMOUNT.toString()}"`),
    );
    expect(track).toHaveBeenCalledWith(
      "cli_buy",
      expect.objectContaining({
        action: "trade",
        success: true,
        input_amount: "100000000000000000",
        input_token_symbol: "ETH",
      }),
    );
  });

  it("executes a buy without an API key configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined);

    await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]);

    expect(setApiKey).not.toHaveBeenCalled();
    expect(tradeCoin).toHaveBeenCalled();
  });

  it("uses the gas buffer for --all", async () => {
    publicClient.getBalance.mockResolvedValue(1000000000000000000n);

    await runBuy([COIN_ADDRESS, "--all", "--yes"]);

    expect(createTradeCall).toHaveBeenCalledWith(
      expect.objectContaining({
        amountIn: 999000000000000000n,
      }),
    );
  });

  it("uses the same gas buffer for --percent 100", async () => {
    publicClient.getBalance.mockResolvedValue(1000000000000000000n);

    await runBuy([COIN_ADDRESS, "--percent", "100", "--yes"]);

    expect(createTradeCall).toHaveBeenCalledWith(
      expect.objectContaining({
        amountIn: 999000000000000000n,
      }),
    );
  });

  it("prompts for confirmation unless --yes is set", async () => {
    await runBuy([COIN_ADDRESS, "--eth", "0.1"]);

    expect(confirm).toHaveBeenCalledWith({
      message: "Confirm?",
      default: false,
    });
  });

  it("exits when address is invalid", async () => {
    await expect(
      runBuy(["not-an-address", "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid address: not-an-address"),
    );
  });

  it("exits when getCoin throws", async () => {
    vi.mocked(getCoin).mockRejectedValue(new Error("network error"));

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Failed to fetch coin"),
    );
  });

  it("exits when coin is not found", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: null },
    } as Awaited<ReturnType<typeof getCoin>>);

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining(`Coin not found: ${COIN_ADDRESS}`),
    );
  });

  it("exits when --eth value is invalid", async () => {
    await expect(
      runBuy([COIN_ADDRESS, "--eth", "abc", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "Invalid --eth value. Must be a positive number.",
      ),
    );
  });

  it("exits when --eth value is zero", async () => {
    await expect(runBuy([COIN_ADDRESS, "--eth", "0", "--yes"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "Invalid --eth value. Must be a positive number.",
      ),
    );
  });

  it("exits when --slippage is invalid", async () => {
    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--slippage", "abc"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --slippage value"),
    );
  });

  it("exits when --slippage is out of range", async () => {
    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--slippage", "100"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --slippage value"),
    );
  });

  it("exits when balance is zero for --all", async () => {
    publicClient.getBalance.mockResolvedValue(0n);

    await expect(runBuy([COIN_ADDRESS, "--all", "--yes"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("No ETH balance"),
    );
  });

  it("exits when balance is too low for gas reserve", async () => {
    publicClient.getBalance.mockResolvedValue(500000000000000n); // 0.0005 ETH

    await expect(runBuy([COIN_ADDRESS, "--all", "--yes"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Balance too low"),
    );
  });

  it("exits when --percent is invalid", async () => {
    publicClient.getBalance.mockResolvedValue(1000000000000000000n);

    await expect(
      runBuy([COIN_ADDRESS, "--percent", "0", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --percent value"),
    );
  });

  it("exits when --percent exceeds 100", async () => {
    publicClient.getBalance.mockResolvedValue(1000000000000000000n);

    await expect(
      runBuy([COIN_ADDRESS, "--percent", "101", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --percent value"),
    );
  });

  it("exits when quote returns zero output", async () => {
    vi.mocked(createTradeCall).mockResolvedValue({
      quote: { amountOut: "0" },
    } as Awaited<ReturnType<typeof createTradeCall>>);

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Quote returned zero output"),
    );
  });

  it("exits when createTradeCall throws", async () => {
    vi.mocked(createTradeCall).mockRejectedValue(new Error("quote error"));

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Quote failed"),
    );
  });

  it("exits when tradeCoin throws", async () => {
    vi.mocked(tradeCoin).mockRejectedValue(new Error("tx reverted"));

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Transaction failed"),
    );
  });

  it("warns but succeeds when receipt parsing fails (tx already on-chain)", async () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    vi.mocked(tradeCoin).mockResolvedValue({
      transactionHash:
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      logs: [], // no Transfer events
    } as Awaited<ReturnType<typeof tradeCoin>>);

    await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]);

    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("transaction succeeded but could not determine"),
    );
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining("Tx: 0x"));
    warnSpy.mockRestore();
  });

  it("aborts with exit code 0 when user declines confirmation", async () => {
    vi.mocked(confirm).mockResolvedValue(false);

    await expect(runBuy([COIN_ADDRESS, "--eth", "0.1"])).rejects.toThrow(
      "process.exit(0)",
    );
  });

  it("prints table output by default", async () => {
    await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]);

    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Bought Test Coin"),
    );
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("Spent"));
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("Received"));
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("Tx"));
  });

  it("calculates percent of balance correctly", async () => {
    publicClient.getBalance.mockResolvedValue(10000000000000000000n); // 10 ETH

    await runBuy([COIN_ADDRESS, "--percent", "50", "--yes"]);

    expect(createTradeCall).toHaveBeenCalledWith(
      expect.objectContaining({
        amountIn: 4999500000000000000n, // 50% of spendable balance (10 ETH - 0.001 ETH gas reserve)
      }),
    );
  });

  it("exits when --percent produces zero amount due to low balance", async () => {
    // 0.0011 ETH — just above gas reserve, tiny percentage rounds to 0 in integer math
    publicClient.getBalance.mockResolvedValue(1100000000000000n);

    await expect(
      runBuy([COIN_ADDRESS, "--percent", "0.001", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Calculated amount is zero"),
    );
  });

  it("produces structured JSON errors when --json is set", async () => {
    await expect(
      runBuy(["not-an-address", "--eth", "0.1", "--yes", "--json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('"error"'));
  });

  describe("--usd flag", () => {
    it("converts USD to ETH amount using fetched price", async () => {
      vi.mocked(fetchTokenPriceUsd).mockResolvedValue(2500);

      await runBuy([COIN_ADDRESS, "--usd", "25", "--yes"]);

      // $25 / $2500 per ETH = 0.01 ETH = 10000000000000000 wei
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 10000000000000000n,
          sell: { type: "eth" },
        }),
      );
      expect(tradeCoin).toHaveBeenCalled();
    });

    it("converts USD to USDC amount with --token usdc", async () => {
      await runBuy([COIN_ADDRESS, "--usd", "10", "--token", "usdc", "--yes"]);

      // $10 / $1 per USDC = 10 USDC = 10000000 (6 decimals)
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 10000000n,
          sell: {
            type: "erc20",
            address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
          },
        }),
      );
    });

    it("exits when --usd value is invalid", async () => {
      await expect(
        runBuy([COIN_ADDRESS, "--usd", "abc", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --usd value"),
      );
    });

    it("exits when --usd value is zero", async () => {
      await expect(
        runBuy([COIN_ADDRESS, "--usd", "0", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --usd value"),
      );
    });

    it("exits when price fetch fails", async () => {
      vi.mocked(fetchTokenPriceUsd).mockResolvedValue(null);

      await expect(
        runBuy([COIN_ADDRESS, "--usd", "10", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Failed to fetch ETH price"),
      );
    });
  });

  describe("--token flag", () => {
    it("defaults to eth", async () => {
      await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]);

      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          sell: { type: "eth" },
        }),
      );
    });

    it("uses USDC trade parameters with --token usdc", async () => {
      await runBuy([COIN_ADDRESS, "--usd", "5", "--token", "usdc", "--yes"]);

      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          sell: {
            type: "erc20",
            address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
          },
        }),
      );
    });

    it("exits with error for invalid --token value", async () => {
      await expect(
        runBuy([COIN_ADDRESS, "--usd", "10", "--token", "btc", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --token value"),
      );
    });
  });

  describe("--quote flag", () => {
    beforeEach(() => {
      vi.mocked(tradeCoin).mockClear();
      vi.mocked(confirm).mockClear();
    });

    it("prints quote as JSON and exits without trading", async () => {
      await runBuy([COIN_ADDRESS, "--eth", "0.1", "--quote", "--json"]);

      expect(tradeCoin).not.toHaveBeenCalled();
      const output = logSpy.mock.calls.map((c) => c[0]).join("");
      expect(output).toContain('"action": "quote"');
      expect(output).toContain('"coin": "TEST"');
      expect(output).toContain('"slippage": 1');
    });

    it("prints quote as table and exits without trading", async () => {
      await runBuy([COIN_ADDRESS, "--eth", "0.1", "--quote"]);

      expect(tradeCoin).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Buy Test Coin (TEST)"),
      );
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("Amount"));
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("You get"));
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("Slippage"));
    });

    it("does not prompt for confirmation with --quote", async () => {
      await runBuy([COIN_ADDRESS, "--eth", "0.1", "--quote"]);

      expect(confirm).not.toHaveBeenCalled();
    });
  });

  describe("--debug flag", () => {
    it("prints request before SDK call and response after on success", async () => {
      publicClient.getBalance.mockResolvedValue(10n ** 18n);

      await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--debug"]);

      const calls = errorSpy.mock.calls.map((c) => c[0]);
      const requestIdx = calls.findIndex(
        (c) => typeof c === "string" && c.includes("Quote Request"),
      );
      const responseIdx = calls.findIndex(
        (c) => typeof c === "string" && c.includes("Quote Response"),
      );
      expect(requestIdx).toBeGreaterThanOrEqual(0);
      expect(responseIdx).toBeGreaterThan(requestIdx);
    });

    it("prints error details when quote throws", async () => {
      publicClient.getBalance.mockResolvedValue(10n ** 18n);
      vi.mocked(createTradeCall).mockRejectedValue(
        new Error("server exploded"),
      );

      await expect(
        runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--debug"]),
      ).rejects.toThrow("process.exit(1)");

      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("[debug] buy — Quote Error"),
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("server exploded"),
      );
    });

    it("prints ZORA_API_TARGET when set", async () => {
      process.env.ZORA_API_TARGET = "http://localhost:9999";
      publicClient.getBalance.mockResolvedValue(10n ** 18n);

      await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--debug"]);

      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("API target: http://localhost:9999"),
      );
      delete process.env.ZORA_API_TARGET;
    });
  });

  it("shows suggestion when quote fails", async () => {
    publicClient.getBalance.mockResolvedValue(10n ** 18n);
    vi.mocked(createTradeCall).mockRejectedValue(new Error("bad request"));

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Use --debug for full error details"),
    );
  });

  describe("--eth with non-ETH tokens", () => {
    it("parses --eth amount using USDC decimals (6) with --token usdc", async () => {
      await runBuy([COIN_ADDRESS, "--eth", "0.01", "--token", "usdc", "--yes"]);

      // 0.01 USDC = 10000 (6 decimals), NOT 10000000000000000 (18 decimals)
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 10000n,
          sell: {
            type: "erc20",
            address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
          },
        }),
      );
    });

    it("parses --eth amount using ZORA decimals (18) with --token zora", async () => {
      await runBuy([COIN_ADDRESS, "--eth", "0.01", "--token", "zora", "--yes"]);

      // 0.01 ZORA = 10000000000000000 (18 decimals)
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 10000000000000000n,
          sell: {
            type: "erc20",
            address: "0x1111111111166b7FE7bd91427724B487980aFc69",
          },
        }),
      );
    });
  });

  describe("--all/--percent with non-ETH tokens", () => {
    it("reads USDC balance for --all --token usdc", async () => {
      // 100 USDC (6 decimals)
      publicClient.readContract.mockResolvedValue(100000000n);

      await runBuy([COIN_ADDRESS, "--all", "--token", "usdc", "--yes"]);

      // Should use USDC balance (100000000), not ETH balance
      expect(publicClient.readContract).toHaveBeenCalledWith(
        expect.objectContaining({
          address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
          functionName: "balanceOf",
          args: [ACCOUNT_ADDRESS],
        }),
      );
      expect(publicClient.getBalance).not.toHaveBeenCalled();
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 100000000n, // full USDC balance, no gas reserve
        }),
      );
    });

    it("reads USDC balance for --percent 50 --token usdc", async () => {
      // 100 USDC (6 decimals)
      publicClient.readContract.mockResolvedValue(100000000n);

      await runBuy([
        COIN_ADDRESS,
        "--percent",
        "50",
        "--token",
        "usdc",
        "--yes",
      ]);

      expect(publicClient.readContract).toHaveBeenCalled();
      expect(publicClient.getBalance).not.toHaveBeenCalled();
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 50000000n, // 50% of 100 USDC
        }),
      );
    });

    it("does not apply gas reserve for ERC-20 tokens with --all", async () => {
      // 1 ZORA (18 decimals)
      publicClient.readContract.mockResolvedValue(1000000000000000000n);

      await runBuy([COIN_ADDRESS, "--all", "--token", "zora", "--yes"]);

      // Full balance, no gas reserve subtracted
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 1000000000000000000n,
        }),
      );
    });
  });

  describe("display and JSON output with non-ETH tokens", () => {
    it("shows correct token symbol in table output", async () => {
      await runBuy([COIN_ADDRESS, "--eth", "10", "--token", "usdc", "--yes"]);

      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("USDC"));
      // Should NOT show "ETH" in the Spent line
      const spentCall = logSpy.mock.calls.find(
        (c) => typeof c[0] === "string" && c[0].includes("Spent"),
      );
      expect(spentCall?.[0]).not.toContain("ETH");
    });

    it("formats JSON spend amount using correct decimals for USDC", async () => {
      await runBuy([
        COIN_ADDRESS,
        "--eth",
        "10",
        "--token",
        "usdc",
        "--yes",
        "--json",
      ]);

      const output = logSpy.mock.calls.map((c) => c[0]).join("");
      const parsed = JSON.parse(output);
      // 10 USDC = 10000000 raw (6 decimals)
      // formatUnits(10000000, 6) = "10"
      expect(parsed.spent.amount).toBe("10");
      expect(parsed.spent.symbol).toBe("USDC");
    });
  });
});
