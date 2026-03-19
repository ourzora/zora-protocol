import { Command } from "commander";
import confirm from "@inquirer/confirm";
import {
  erc20Abi,
  formatUnits,
  isAddress,
  isAddressEqual,
  parseEventLogs,
  parseUnits,
  type Address,
  type TransactionReceipt,
} from "viem";
import {
  createTradeCall,
  getCoin,
  setApiKey,
  tradeCoin,
} from "@zoralabs/coins-sdk";
import { resolveAccount, createClients } from "../lib/wallet.js";
import { getApiKey } from "../lib/config.js";

const BASE_OUTPUT_TOKENS = {
  eth: {
    symbol: "ETH",
    decimals: 18,
    trade: { type: "eth" as const },
  },
  usdc: {
    symbol: "USDC",
    decimals: 6,
    trade: {
      type: "erc20" as const,
      address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" as Address,
    },
  },
  zora: {
    symbol: "ZORA",
    decimals: 18,
    trade: {
      type: "erc20" as const,
      address: "0x1111111111166b7FE7bd91427724B487980aFc69" as Address,
    },
  },
} as const;

type OutputAsset = keyof typeof BASE_OUTPUT_TOKENS;

const amountModeChecks = {
  amount: (opts: { amount?: string }) => opts.amount !== undefined,
  percent: (opts: { percent?: string }) => opts.percent !== undefined,
  all: (opts: { all?: boolean }) => opts.all === true,
} as const;

type AmountMode = keyof typeof amountModeChecks;

function getAmountMode(opts: Record<string, unknown>): AmountMode {
  const provided = (
    Object.entries(amountModeChecks) as Array<
      [AmountMode, (typeof amountModeChecks)[AmountMode]]
    >
  )
    .filter(([, isProvided]) => isProvided(opts as never))
    .map(([mode]) => mode);

  if (provided.length === 0) {
    console.error("Specify one amount flag: --amount, --percent, or --all");
    process.exit(1);
  }

  if (provided.length > 1) {
    console.error(
      "Only one amount flag allowed: --amount, --percent, or --all",
    );
    process.exit(1);
  }

  return provided[0];
}

function parsePercentageLikeValue(value: string): number | undefined {
  if (!/^\d+(\.\d+)?$/.test(value)) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function formatAmountDisplay(amount: bigint, decimals: number): string {
  const formatted = formatUnits(amount, decimals);
  // Truncate to 2 decimal places before converting to Number to avoid precision loss
  const parts = formatted.split(".");
  const truncated = parts[1]
    ? `${parts[0]}.${parts[1].slice(0, 2)}`
    : formatted;
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 2,
  }).format(Number(truncated));
}

function getReceivedErc20AmountFromReceipt({
  receipt,
  tokenAddress,
  recipient,
}: {
  receipt: TransactionReceipt;
  tokenAddress: Address;
  recipient: Address;
}): bigint {
  const transfers = parseEventLogs({
    abi: erc20Abi,
    eventName: "Transfer",
    logs: receipt.logs,
    strict: false,
  });

  const matchingTransfers = transfers.filter((transfer) => {
    const to = transfer.args?.to;
    if (!to) return false;
    return (
      isAddressEqual(transfer.address, tokenAddress) &&
      isAddressEqual(to, recipient)
    );
  });

  if (matchingTransfers.length === 0) {
    throw new Error("No matching Transfer event found in receipt.");
  }

  return matchingTransfers.reduce((total, transfer) => {
    const value = transfer.args?.value;
    if (value === undefined) {
      throw new Error("Transfer event missing amount.");
    }
    return total + value;
  }, 0n);
}

function printJson(data: Record<string, unknown>): void {
  console.log(JSON.stringify(data, null, 2));
}

function printSellQuote(
  output: "table" | "json",
  info: {
    coinName: string;
    coinSymbol: string;
    address: string;
    soldFormatted: string;
    amountIn: bigint;
    coinDecimals: number;
    receivedFormatted: string;
    quoteAmountOut: string;
    outputSymbol: string;
    outputDecimals: number;
    slippagePct: number;
  },
): void {
  if (output === "json") {
    printJson({
      action: "quote",
      coin: info.coinSymbol,
      address: info.address,
      sell: {
        amount: formatUnits(info.amountIn, info.coinDecimals),
        raw: info.amountIn.toString(),
        symbol: info.coinSymbol,
      },
      estimated: {
        amount: formatUnits(BigInt(info.quoteAmountOut), info.outputDecimals),
        raw: info.quoteAmountOut,
        symbol: info.outputSymbol,
      },
      slippage: info.slippagePct,
    });
    return;
  }

  console.log(`\n Sell ${info.coinName} (${info.coinSymbol})\n`);
  console.log(`   Amount       ${info.soldFormatted} ${info.coinSymbol}`);
  console.log(
    `   You get      ~${info.receivedFormatted} ${info.outputSymbol}`,
  );
  console.log(`   Slippage     ${info.slippagePct}%\n`);
}

function printSellResult(
  output: "table" | "json",
  info: {
    coinName: string;
    coinSymbol: string;
    address: string;
    amountIn: bigint;
    coinDecimals: number;
    soldFormatted: string;
    receivedAmountOut: bigint;
    outputSymbol: string;
    outputDecimals: number;
    receivedSource: "receipt" | "quote";
    txHash: string;
  },
): void {
  const receivedAmount = formatUnits(
    info.receivedAmountOut,
    info.outputDecimals,
  );
  const receivedFormatted = formatAmountDisplay(
    info.receivedAmountOut,
    info.outputDecimals,
  );

  if (output === "json") {
    printJson({
      action: "sell",
      coin: info.coinSymbol,
      address: info.address,
      sold: {
        amount: formatUnits(info.amountIn, info.coinDecimals),
        raw: info.amountIn.toString(),
        symbol: info.coinSymbol,
      },
      received: {
        amount: receivedAmount,
        raw: info.receivedAmountOut.toString(),
        symbol: info.outputSymbol,
        source: info.receivedSource,
      },
      tx: info.txHash,
    });
    return;
  }

  console.log(`\n Sold ${info.coinName}\n`);
  console.log(`   Sold         ${info.soldFormatted} ${info.coinSymbol}`);
  console.log(
    `   Received     ${info.receivedSource === "quote" ? "~" : ""}${receivedFormatted} ${info.outputSymbol}`,
  );
  if (info.receivedSource === "quote") {
    console.log("   Note         based on quote");
  }
  console.log(`   Tx           ${info.txHash}\n`);
}

export const sellCommand = new Command("sell")
  .description("Sell a coin")
  .argument("<address>", "Coin contract address (0x…)")
  .option("--amount <value>", "Sell specific number of coins")
  .option("--percent <value>", "Sell percentage of coin balance")
  .option("--all", "Sell entire coin balance")
  .option("--to <asset>", "Receive asset: eth, usdc, zora", "eth")
  .option("--quote", "Print quote and exit without trading")
  .option("--yes", "Skip confirmation prompt")
  .option("--slippage <pct>", "Slippage tolerance percent", "1")
  .option("-o, --output <format>", "Output format: table, json", "table")
  .action(async (coinAddress: string, opts) => {
    if (!isAddress(coinAddress)) {
      console.error(`Invalid address: ${coinAddress}`);
      process.exit(1);
    }

    const output = opts.output as "table" | "json";
    if (output !== "table" && output !== "json") {
      console.error(`Invalid --output value: ${output}. Use: table, json`);
      process.exit(1);
    }

    const outputAsset = opts.to as string;
    if (!(outputAsset in BASE_OUTPUT_TOKENS)) {
      console.error(`Invalid --to value: ${outputAsset}. Use: eth, usdc, zora`);
      process.exit(1);
    }
    const outputToken = BASE_OUTPUT_TOKENS[outputAsset as OutputAsset];

    const amountMode = getAmountMode(opts);

    const slippagePct = parsePercentageLikeValue(opts.slippage);
    if (slippagePct === undefined || slippagePct < 0 || slippagePct > 99) {
      console.error("Invalid --slippage value. Must be between 0 and 99.");
      process.exit(1);
    }
    const slippage = slippagePct / 100;

    const apiKey = getApiKey();
    if (!apiKey) {
      console.error(
        "Not authenticated. Run 'zora auth configure' to set your API key.",
      );
      process.exit(1);
    }
    setApiKey(apiKey);

    const account = resolveAccount();
    const { publicClient, walletClient } = createClients(account);

    let token;
    try {
      const response = await getCoin({ address: coinAddress });
      token = response.data?.zora20Token;
    } catch (err) {
      console.error(
        `Failed to fetch coin: ${err instanceof Error ? err.message : String(err)}`,
      );
      return process.exit(1);
    }
    if (!token) {
      console.error(`Coin not found: ${coinAddress}`);
      process.exit(1);
    }

    const coinName = token.name;
    const coinSymbol = token.symbol;
    const coinDecimals = Number(token.decimals ?? 18);

    let amountIn: bigint;

    if (amountMode === "amount") {
      const val = parsePercentageLikeValue(opts.amount);
      if (val === undefined || val <= 0) {
        console.error("Invalid --amount value. Must be a positive number.");
        process.exit(1);
      }
      try {
        amountIn = parseUnits(opts.amount, coinDecimals);
      } catch {
        console.error("Invalid --amount value for token decimals.");
        process.exit(1);
      }
    } else {
      const balance = await publicClient.readContract({
        abi: erc20Abi,
        address: coinAddress as Address,
        functionName: "balanceOf",
        args: [account.address],
      });

      if (balance === 0n) {
        console.error(
          `No ${coinSymbol} balance. Buy some first or pick a different wallet.`,
        );
        process.exit(1);
      }

      if (amountMode === "all") {
        amountIn = balance;
      } else {
        const pct = parsePercentageLikeValue(opts.percent);
        if (pct === undefined || pct <= 0 || pct > 100) {
          console.error("Invalid --percent value. Must be between 0 and 100.");
          process.exit(1);
        }

        amountIn =
          pct === 100
            ? balance
            : (balance * BigInt(Math.round(pct * 100))) / 10000n;

        if (amountIn === 0n) {
          console.error("Calculated amount is zero. Balance too low.");
          process.exit(1);
        }
      }
    }

    const tradeParameters = {
      sell: { type: "erc20" as const, address: coinAddress as Address },
      buy: outputToken.trade,
      amountIn,
      slippage,
      sender: account.address,
    };

    let quoteAmountOut: string;
    try {
      const quote = await createTradeCall(tradeParameters);
      if (!quote.quote?.amountOut || quote.quote.amountOut === "0") {
        console.error("Quote returned zero output. Amount may be too small.");
        process.exit(1);
      }
      quoteAmountOut = quote.quote.amountOut;
    } catch (err) {
      console.error(
        `Quote failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      process.exit(1);
    }

    const soldFormatted = formatAmountDisplay(amountIn, coinDecimals);
    const receivedFormatted = formatAmountDisplay(
      BigInt(quoteAmountOut),
      outputToken.decimals,
    );

    // --quote: print quote and exit
    if (opts.quote) {
      printSellQuote(output, {
        coinName,
        coinSymbol,
        address: coinAddress,
        soldFormatted,
        amountIn,
        coinDecimals,
        receivedFormatted,
        quoteAmountOut,
        outputSymbol: outputToken.symbol,
        outputDecimals: outputToken.decimals,
        slippagePct,
      });
      return;
    }

    if (!opts.yes) {
      printSellQuote("table", {
        coinName,
        coinSymbol,
        address: coinAddress,
        soldFormatted,
        amountIn,
        coinDecimals,
        receivedFormatted,
        quoteAmountOut,
        outputSymbol: outputToken.symbol,
        outputDecimals: outputToken.decimals,
        slippagePct,
      });

      const ok = await confirm({
        message: "Confirm?",
        default: false,
      });
      if (!ok) {
        console.error("Aborted.");
        process.exit(0);
      }
    }

    let receipt: TransactionReceipt;
    let txHash: string;
    let receivedAmountOut = BigInt(quoteAmountOut);
    let receivedSource: "receipt" | "quote" = "quote";
    try {
      receipt = await tradeCoin({
        tradeParameters,
        walletClient,
        publicClient,
        account,
      });
    } catch (err) {
      console.error(
        `Transaction failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      process.exit(1);
    }
    txHash = receipt.transactionHash;

    // For ERC-20 outputs, try to get actual received amount from receipt
    if (outputToken.trade.type === "erc20") {
      try {
        receivedAmountOut = getReceivedErc20AmountFromReceipt({
          receipt,
          tokenAddress: outputToken.trade.address,
          recipient: account.address,
        });
        receivedSource = "receipt";
      } catch {
        // Fall back to quote amount
      }
    }

    printSellResult(output, {
      coinName,
      coinSymbol,
      address: coinAddress,
      amountIn,
      coinDecimals,
      soldFormatted,
      receivedAmountOut,
      outputSymbol: outputToken.symbol,
      outputDecimals: outputToken.decimals,
      receivedSource,
      txHash,
    });
  });
