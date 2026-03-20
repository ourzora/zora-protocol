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

vi.mock("@zoralabs/coins-sdk", () => ({
  setApiKey: vi.fn(),
  getCoin: vi.fn(),
  createTradeCall: vi.fn(),
  tradeCoin: vi.fn(),
}));

vi.mock("../lib/wallet-balances.js", () => ({
  fetchTokenPriceUsd: vi.fn(),
}));

import confirm from "@inquirer/confirm";
import {
  createTradeCall,
  getCoin,
  setApiKey,
  tradeCoin,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { createClients, resolveAccount } from "../lib/wallet.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";

const COIN_ADDRESS = "0x1234567890abcdef1234567890abcdef12345678" as Address;
const ACCOUNT_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" as Address;
const RECEIPT_USDC_AMOUNT = 25_000_000n;

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

async function runSell(args: string[]) {
  const { sellCommand } = await import("./sell.js");
  return sellCommand.parseAsync(args, { from: "user" });
}

describe("sell command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  const publicClient = {
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
          decimals: 18,
        },
      },
    } as Awaited<ReturnType<typeof getCoin>>);
    vi.mocked(createTradeCall).mockResolvedValue({
      quote: {
        amountOut: "20000000",
      },
    } as Awaited<ReturnType<typeof createTradeCall>>);
    vi.mocked(tradeCoin).mockResolvedValue({
      transactionHash:
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      logs: [
        makeTransferLog({
          tokenAddress: USDC_ADDRESS,
          from: "0x000000000000000000000000000000000000dead",
          to: ACCOUNT_ADDRESS,
          value: RECEIPT_USDC_AMOUNT,
        }),
      ],
    } as Awaited<ReturnType<typeof tradeCoin>>);
    vi.mocked(confirm).mockResolvedValue(true);
    vi.mocked(fetchTokenPriceUsd).mockResolvedValue(2.0);
    publicClient.readContract.mockResolvedValue(0n);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("only exposes supported sell amount flags", async () => {
    const { sellCommand } = await import("./sell.js");
    const optionNames = sellCommand.options.map((option) => option.long);

    expect(optionNames).toContain("--amount");
    expect(optionNames).toContain("--percent");
    expect(optionNames).toContain("--all");
    expect(optionNames).toContain("--to");
    expect(optionNames).not.toContain("--eth");
  });

  it("exits when no amount flag is provided", async () => {
    await expect(runSell([COIN_ADDRESS])).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "Specify one amount flag: --amount, --usd, --percent, or --all",
      ),
    );
  });

  it("exits when multiple amount flags are provided", async () => {
    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--percent", "25"]),
    ).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "Only one amount flag allowed: --amount, --usd, --percent, or --all",
      ),
    );
  });

  it("rejects unsupported legacy flags as unknown options", async () => {
    const stderrSpy = vi
      .spyOn(process.stderr, "write")
      .mockImplementation(() => true);

    await expect(runSell([COIN_ADDRESS, "--eth", "0.1"])).rejects.toThrow();

    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("unknown option '--eth'"),
    );

    stderrSpy.mockRestore();
  });

  it("exits with error for invalid address", async () => {
    await expect(runSell(["not-an-address", "--amount", "1"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid address"),
    );
  });

  it("exits with error for invalid --to value", async () => {
    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--to", "btc"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --to value"),
    );
  });

  it("exits with error for invalid --output value", async () => {
    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--output", "csv"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --output value"),
    );
  });

  it("exits with error when no API key is configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined);

    await expect(runSell([COIN_ADDRESS, "--amount", "1"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Not authenticated"),
    );
  });

  it("exits with error when getCoin throws", async () => {
    vi.mocked(getCoin).mockRejectedValue(new Error("Network error"));

    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Failed to fetch coin"),
    );
  });

  it("exits with error when coin not found", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: null },
    } as Awaited<ReturnType<typeof getCoin>>);

    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Coin not found"),
    );
  });

  it("exits with error for invalid --amount value", async () => {
    await expect(
      runSell([COIN_ADDRESS, "--amount", "abc", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --amount"),
    );
  });

  it("exits with error for negative --amount", async () => {
    await expect(
      runSell([COIN_ADDRESS, "--amount", "-5", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --amount"),
    );
  });

  it("exits with error for invalid --percent value", async () => {
    publicClient.readContract.mockResolvedValue(1000000000000000000n);

    await expect(
      runSell([COIN_ADDRESS, "--percent", "150", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --percent"),
    );
  });

  it("exits with error when token balance is zero for --all", async () => {
    publicClient.readContract.mockResolvedValue(0n);

    await expect(runSell([COIN_ADDRESS, "--all", "--yes"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("No TEST balance"),
    );
  });

  it("exits with error when quote returns zero", async () => {
    vi.mocked(createTradeCall).mockResolvedValue({
      quote: { amountOut: "0" },
    } as Awaited<ReturnType<typeof createTradeCall>>);

    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Quote returned zero"),
    );
  });

  it("exits with error when quote throws", async () => {
    vi.mocked(createTradeCall).mockRejectedValue(new Error("API down"));

    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Quote failed"),
    );
  });

  it("exits with error when tradeCoin throws", async () => {
    vi.mocked(tradeCoin).mockRejectedValue(new Error("tx reverted"));

    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Transaction failed"),
    );
  });

  it("aborts when user declines confirmation", async () => {
    vi.mocked(confirm).mockResolvedValue(false);

    await expect(runSell([COIN_ADDRESS, "--amount", "1"])).rejects.toThrow(
      "process.exit(0)",
    );
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
  });

  it("executes a sell to USDC and prints receipt-based JSON output", async () => {
    await runSell([
      COIN_ADDRESS,
      "--amount",
      "1.5",
      "--to",
      "usdc",
      "--yes",
      "--output",
      "json",
    ]);

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(createTradeCall).toHaveBeenCalledWith(
      expect.objectContaining({
        amountIn: 1500000000000000000n,
        buy: {
          type: "erc20",
          address: USDC_ADDRESS,
        },
        sender: ACCOUNT_ADDRESS,
      }),
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining('"action": "sell"'),
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining('"amount": "25"'),
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining('"source": "receipt"'),
    );
  });

  it("uses full token balance for --all", async () => {
    publicClient.readContract.mockResolvedValue(1500000000000000000n);

    await runSell([COIN_ADDRESS, "--all", "--yes"]);

    expect(createTradeCall).toHaveBeenCalledWith(
      expect.objectContaining({
        amountIn: 1500000000000000000n,
      }),
    );
  });

  it("uses full token balance for --percent 100", async () => {
    publicClient.readContract.mockResolvedValue(1500000000000000000n);

    await runSell([COIN_ADDRESS, "--percent", "100", "--yes"]);

    expect(createTradeCall).toHaveBeenCalledWith(
      expect.objectContaining({
        amountIn: 1500000000000000000n,
      }),
    );
  });

  it("falls back to the quote for ETH output", async () => {
    vi.mocked(createTradeCall).mockResolvedValue({
      quote: {
        amountOut: "100000000000000000",
      },
    } as Awaited<ReturnType<typeof createTradeCall>>);

    await runSell([
      COIN_ADDRESS,
      "--amount",
      "1",
      "--to",
      "eth",
      "--yes",
      "--output",
      "json",
    ]);

    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining('"source": "quote"'),
    );
  });

  it("prints table output for sell result", async () => {
    await runSell([COIN_ADDRESS, "--amount", "1.5", "--to", "usdc", "--yes"]);

    const output = logSpy.mock.calls.map((call) => call[0]).join("\n");
    expect(output).toContain("Sold Test Coin");
    expect(output).toContain("TEST");
  });

  it("prompts for confirmation unless --yes is set", async () => {
    await runSell([COIN_ADDRESS, "--amount", "1"]);

    expect(confirm).toHaveBeenCalledWith({
      message: "Confirm?",
      default: false,
    });
  });

  it("produces structured JSON errors when --output json is set", async () => {
    await expect(
      runSell(["not-an-address", "--amount", "1", "--yes", "--output", "json"]),
    ).rejects.toThrow("process.exit(1)");
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining('"error"'));
  });

  describe("--usd flag", () => {
    it("converts USD to coin amount using fetched price", async () => {
      vi.mocked(fetchTokenPriceUsd).mockResolvedValue(2.0);

      await runSell([COIN_ADDRESS, "--usd", "10", "--yes"]);

      // $10 / $2.0 per coin = 5 coins = 5000000000000000000 (18 decimals)
      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          amountIn: 5000000000000000000n,
        }),
      );
      expect(tradeCoin).toHaveBeenCalled();
    });

    it("exits when --usd value is invalid", async () => {
      await expect(
        runSell([COIN_ADDRESS, "--usd", "abc", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --usd value"),
      );
    });

    it("exits when --usd value is zero", async () => {
      await expect(
        runSell([COIN_ADDRESS, "--usd", "0", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --usd value"),
      );
    });

    it("exits when coin price fetch fails", async () => {
      vi.mocked(fetchTokenPriceUsd).mockResolvedValue(null);

      await expect(
        runSell([COIN_ADDRESS, "--usd", "10", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Failed to fetch TEST price"),
      );
    });
  });

  describe("--token flag (alias for --to)", () => {
    it("uses --token value when provided", async () => {
      await runSell([
        COIN_ADDRESS,
        "--amount",
        "1",
        "--token",
        "usdc",
        "--yes",
      ]);

      expect(createTradeCall).toHaveBeenCalledWith(
        expect.objectContaining({
          buy: {
            type: "erc20",
            address: USDC_ADDRESS,
          },
        }),
      );
    });

    it("exits with error for invalid --token value", async () => {
      await expect(
        runSell([COIN_ADDRESS, "--amount", "1", "--token", "btc"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --token value"),
      );
    });
  });

  it("prints quote and exits with --quote flag", async () => {
    vi.mocked(tradeCoin).mockClear();

    await runSell([
      COIN_ADDRESS,
      "--amount",
      "1",
      "--quote",
      "--output",
      "json",
    ]);

    const output = logSpy.mock.calls.map((call) => call[0]).join("\n");
    expect(output).toContain('"action": "quote"');
    expect(tradeCoin).not.toHaveBeenCalled();
  });

  it("prints table quote with --quote flag", async () => {
    vi.mocked(tradeCoin).mockClear();

    await runSell([COIN_ADDRESS, "--amount", "1", "--quote"]);

    const output = logSpy.mock.calls.map((call) => call[0]).join("\n");
    expect(output).toContain("Sell Test Coin");
    expect(tradeCoin).not.toHaveBeenCalled();
  });

  describe("--debug flag", () => {
    it("prints request before SDK call and response after on success", async () => {
      await runSell([COIN_ADDRESS, "--amount", "1", "--yes", "--debug"]);

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
      vi.mocked(createTradeCall).mockRejectedValue(
        new Error("server exploded"),
      );

      await expect(
        runSell([COIN_ADDRESS, "--amount", "1", "--yes", "--debug"]),
      ).rejects.toThrow("process.exit(1)");

      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("[debug] sell — Quote Error"),
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("server exploded"),
      );
    });

    it("prints ZORA_API_TARGET when set", async () => {
      process.env.ZORA_API_TARGET = "http://localhost:9999";

      await runSell([COIN_ADDRESS, "--amount", "1", "--yes", "--debug"]);

      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("API target: http://localhost:9999"),
      );
      delete process.env.ZORA_API_TARGET;
    });
  });

  it("shows suggestion when quote fails", async () => {
    vi.mocked(createTradeCall).mockRejectedValue(new Error("bad request"));

    await expect(
      runSell([COIN_ADDRESS, "--amount", "1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Use --debug for full error details"),
    );
  });
});
