import { Command } from "commander";
import confirm from "@inquirer/confirm";
import {
  parseEther,
  formatEther,
  formatUnits,
  isAddress,
  erc20Abi,
  isAddressEqual,
  parseEventLogs,
  type Address,
  type TransactionReceipt,
} from "viem";
import {
  setApiKey,
  getCoin,
  tradeCoin,
  createTradeCall,
} from "@zoralabs/coins-sdk";
import { resolveAccount, createClients } from "../lib/wallet.js";
import { getApiKey } from "../lib/config.js";

function formatEthDisplay(wei: bigint): string {
  const eth = formatEther(wei);
  // Trim trailing zeros but keep at least one decimal
  const parts = eth.split(".");
  if (!parts[1]) return eth;
  const trimmed = parts[1].replace(/0+$/, "") || "0";
  return `${parts[0]}.${trimmed}`;
}

const GAS_RESERVE = parseEther("0.001");
const amountModeChecks = {
  eth: (opts: { eth?: string }) => opts.eth !== undefined,
  percent: (opts: { percent?: string }) => opts.percent !== undefined,
  all: (opts: { all?: boolean }) => opts.all === true,
} as const;

type AmountMode = keyof typeof amountModeChecks;

function getAmountMode(opts: {
  eth?: string;
  percent?: string;
  all?: boolean;
}): AmountMode {
  const provided = (
    Object.entries(amountModeChecks) as Array<
      [AmountMode, (typeof amountModeChecks)[AmountMode]]
    >
  )
    .filter(([, isProvided]) => isProvided(opts))
    .map(([mode]) => mode);

  if (provided.length === 0) {
    console.error("Specify one amount flag: --eth, --percent, or --all");
    process.exit(1);
  }

  if (provided.length > 1) {
    console.error("Only one amount flag allowed.");
    process.exit(1);
  }

  return provided[0];
}

function parsePercentageLikeValue(value: string): number | undefined {
  if (!/^\d+(\.\d+)?$/.test(value)) return undefined;

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function getReceivedAmountFromReceipt({
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

function formatCoinsDisplay(coinsOut: string): string {
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 2,
  }).format(Number(coinsOut));
}

interface QuoteInfo {
  coinName: string;
  coinSymbol: string;
  address: string;
  ethAmount: string;
  amountIn: bigint;
  coinsFormatted: string;
  amountOut: string;
  slippagePct: number;
}

function printQuote(output: "table" | "json", info: QuoteInfo): void {
  if (output === "json") {
    printJson({
      action: "quote",
      coin: info.coinSymbol,
      address: info.address,
      spend: {
        eth: formatEther(info.amountIn),
        wei: info.amountIn.toString(),
      },
      estimated: {
        amount: formatUnits(BigInt(info.amountOut), 18),
        raw: info.amountOut,
        symbol: info.coinSymbol,
      },
      slippage: info.slippagePct,
    });
    return;
  }

  console.log(`\n Buy ${info.coinName} (${info.coinSymbol})\n`);
  console.log(`   Amount       ${info.ethAmount} ETH`);
  console.log(`   You get      ~${info.coinsFormatted} ${info.coinSymbol}`);
  console.log(`   Slippage     ${info.slippagePct}%\n`);
}

interface TradeResultInfo {
  coinName: string;
  coinSymbol: string;
  address: string;
  ethAmount: string;
  amountIn: bigint;
  receivedAmountOut: bigint;
  txHash: string;
}

function printTradeResult(
  output: "table" | "json",
  info: TradeResultInfo,
): void {
  const receivedAmount = formatUnits(info.receivedAmountOut, 18);
  const receivedFormatted = formatCoinsDisplay(receivedAmount);

  if (output === "json") {
    printJson({
      action: "buy",
      coin: info.coinSymbol,
      address: info.address,
      spent: {
        eth: formatEther(info.amountIn),
        wei: info.amountIn.toString(),
      },
      received: {
        amount: receivedAmount,
        raw: info.receivedAmountOut.toString(),
        symbol: info.coinSymbol,
      },
      tx: info.txHash,
    });
    return;
  }

  console.log(`\n Bought ${info.coinName}\n`);
  console.log(`   Spent        ${info.ethAmount} ETH`);
  console.log(`   Received     ${receivedFormatted} ${info.coinSymbol}`);
  console.log(`   Tx           ${info.txHash}\n`);
}

export const buyCommand = new Command("buy")
  .description("Buy a coin")
  .argument("<address>", "Coin contract address (0x…)")
  .option("--eth <value>", "Buy with ETH amount")
  .option("--percent <value>", "Buy with percentage of ETH balance")
  .option("--all", "Swap all ETH for coin")
  .option("--quote", "Print quote and exit without trading")
  .option("--yes", "Skip confirmation prompt")
  .option("--slippage <pct>", "Slippage tolerance percent", "1")
  .option("-o, --output <format>", "Output format: table, json", "table")
  .action(async (coinAddress: string, opts) => {
    // Validate address
    if (!isAddress(coinAddress)) {
      console.error(`Invalid address: ${coinAddress}`);
      process.exit(1);
    }

    // Validate output format
    const output = opts.output as "table" | "json";
    if (output !== "table" && output !== "json") {
      console.error(`Invalid --output value: ${output}. Use: table, json`);
      process.exit(1);
    }

    const amountMode = getAmountMode(opts);

    // Parse slippage
    const slippagePct = parsePercentageLikeValue(opts.slippage);
    if (slippagePct === undefined || slippagePct < 0 || slippagePct > 99) {
      console.error("Invalid --slippage value. Must be between 0 and 99.");
      process.exit(1);
    }
    const slippage = slippagePct / 100;

    // Auth
    const apiKey = getApiKey();
    if (!apiKey) {
      console.error(
        "Not authenticated. Run 'zora auth configure' to set your API key.",
      );
      process.exit(1);
    }
    setApiKey(apiKey);

    // Wallet
    const account = resolveAccount();
    const { publicClient, walletClient } = createClients(account);

    // Get coin info
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

    // Calculate amountIn (ETH in wei)
    let amountIn: bigint;

    if (amountMode === "eth") {
      const val = parsePercentageLikeValue(opts.eth);
      if (val === undefined || val <= 0) {
        console.error("Invalid --eth value. Must be a positive number.");
        process.exit(1);
      }
      try {
        amountIn = parseEther(opts.eth);
      } catch {
        console.error("Invalid --eth value. Must be a positive number.");
        process.exit(1);
      }
    } else {
      // Balance-based modes need to preserve enough ETH for gas.
      const balance = await publicClient.getBalance({
        address: account.address,
      });
      if (balance === 0n) {
        console.error(
          `No ETH balance. Deposit ETH to ${account.address} on Base.`,
        );
        process.exit(1);
      }

      if (balance <= GAS_RESERVE) {
        console.error(
          `Balance too low (${formatEthDisplay(balance)} ETH). Need >0.001 ETH for gas.`,
        );
        process.exit(1);
      }

      const spendableBalance = balance - GAS_RESERVE;

      if (amountMode === "all") {
        amountIn = spendableBalance;
      } else {
        const pct = parsePercentageLikeValue(opts.percent);
        if (pct === undefined || pct <= 0 || pct > 100) {
          console.error("Invalid --percent value. Must be between 0 and 100.");
          process.exit(1);
        }

        amountIn =
          pct === 100
            ? spendableBalance
            : (balance * BigInt(Math.round(pct * 100))) / 10000n;

        if (amountIn === 0n) {
          console.error("Calculated amount is zero. Balance too low.");
          process.exit(1);
        }
      }
    }

    // Get quote
    const tradeParameters = {
      sell: { type: "eth" as const },
      buy: { type: "erc20" as const, address: coinAddress as Address },
      amountIn,
      slippage,
      sender: account.address,
    };

    let amountOut: string;
    try {
      const quote = await createTradeCall(tradeParameters);
      if (!quote.quote?.amountOut || quote.quote.amountOut === "0") {
        console.error("Quote returned zero output. Amount may be too small.");
        process.exit(1);
      }
      amountOut = quote.quote.amountOut;
    } catch (err) {
      console.error(
        `Quote failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      process.exit(1);
    }

    // Format quote for display
    const ethAmount = formatEthDisplay(amountIn);
    const coinsOut = formatUnits(BigInt(amountOut), 18);
    const coinsFormatted = formatCoinsDisplay(coinsOut);

    // --quote: print quote and exit
    if (opts.quote) {
      printQuote(output, {
        coinName,
        coinSymbol,
        address: coinAddress,
        ethAmount,
        amountIn,
        coinsFormatted,
        amountOut,
        slippagePct,
      });
      return;
    }

    // Confirmation prompt
    if (!opts.yes) {
      printQuote("table", {
        coinName,
        coinSymbol,
        address: coinAddress,
        ethAmount,
        amountIn,
        coinsFormatted,
        amountOut,
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

    // Execute trade
    let receipt: TransactionReceipt;
    let txHash: string;
    let receivedAmountOut = BigInt(amountOut);
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

    try {
      receivedAmountOut = getReceivedAmountFromReceipt({
        receipt,
        tokenAddress: coinAddress as Address,
        recipient: account.address,
      });
    } catch (err) {
      console.error(
        `Transaction succeeded but could not determine received amount: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      console.error(`Tx: ${txHash}`);
      process.exit(0);
    }

    printTradeResult(output, {
      coinName,
      coinSymbol,
      address: coinAddress,
      ethAmount,
      amountIn,
      receivedAmountOut,
      txHash,
    });
  });
