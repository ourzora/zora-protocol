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

import confirm from "@inquirer/confirm";
import {
  createTradeCall,
  getCoin,
  setApiKey,
  tradeCoin,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { createClients, resolveAccount } from "../lib/wallet.js";

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

async function runBuy(args: string[]) {
  const { buyCommand } = await import("./buy.js");
  return buyCommand.parseAsync(args, { from: "user" });
}

describe("buy command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  const publicClient = {
    getBalance: vi.fn(),
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
    publicClient.getBalance.mockResolvedValue(0n);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("only exposes supported amount flags", async () => {
    const { buyCommand } = await import("./buy.js");
    const optionNames = buyCommand.options.map((option) => option.long);

    expect(optionNames).toContain("--eth");
    expect(optionNames).toContain("--percent");
    expect(optionNames).toContain("--all");
    expect(optionNames).not.toContain("--usd");
    expect(optionNames).not.toContain("--amount");
  });

  it("exits when no amount flag is provided", async () => {
    await expect(runBuy([COIN_ADDRESS])).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith(
      "Specify one amount flag: --eth, --percent, or --all",
    );
  });

  it("exits when multiple amount flags are provided", async () => {
    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--percent", "25"]),
    ).rejects.toThrow("process.exit(1)");

    expect(errorSpy).toHaveBeenCalledWith("Only one amount flag allowed.");
  });

  it("rejects removed unsupported flags as unknown options", async () => {
    const stderrSpy = vi
      .spyOn(process.stderr, "write")
      .mockImplementation(() => true);

    await expect(runBuy([COIN_ADDRESS, "--usd", "10"])).rejects.toThrow();

    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("unknown option '--usd'"),
    );

    stderrSpy.mockRestore();
  });

  it("executes an ETH buy and prints JSON output", async () => {
    await runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--output", "json"]);

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
    expect(errorSpy).toHaveBeenCalledWith("Invalid address: not-an-address");
  });

  it("exits when --output is invalid", async () => {
    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes", "--output", "csv"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --output value"),
    );
  });

  it("exits when no API key is configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as unknown as string);

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Not authenticated"),
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
    expect(errorSpy).toHaveBeenCalledWith(`Coin not found: ${COIN_ADDRESS}`);
  });

  it("exits when --eth value is invalid", async () => {
    await expect(
      runBuy([COIN_ADDRESS, "--eth", "abc", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      "Invalid --eth value. Must be a positive number.",
    );
  });

  it("exits when --eth value is zero", async () => {
    await expect(runBuy([COIN_ADDRESS, "--eth", "0", "--yes"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      "Invalid --eth value. Must be a positive number.",
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

  it("exits 0 when receipt parsing fails (tx already succeeded)", async () => {
    vi.mocked(tradeCoin).mockResolvedValue({
      transactionHash:
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      logs: [], // no Transfer events
    } as Awaited<ReturnType<typeof tradeCoin>>);

    await expect(
      runBuy([COIN_ADDRESS, "--eth", "0.1", "--yes"]),
    ).rejects.toThrow("process.exit(0)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Transaction succeeded but could not determine"),
    );
    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Tx: 0x"));
  });

  it("aborts when user declines confirmation", async () => {
    vi.mocked(confirm).mockResolvedValue(false);

    await expect(runBuy([COIN_ADDRESS, "--eth", "0.1"])).rejects.toThrow(
      "process.exit(0)",
    );
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
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
        amountIn: 5000000000000000000n, // 50% of 10 ETH
      }),
    );
  });

  describe("--quote flag", () => {
    beforeEach(() => {
      vi.mocked(tradeCoin).mockClear();
      vi.mocked(confirm).mockClear();
    });

    it("prints quote as JSON and exits without trading", async () => {
      await runBuy([
        COIN_ADDRESS,
        "--eth",
        "0.1",
        "--quote",
        "--output",
        "json",
      ]);

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
});
