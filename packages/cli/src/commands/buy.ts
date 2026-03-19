import { Command } from "commander";
import confirm from "@inquirer/confirm";
import { parseEther, formatUnits, isAddress, type Address } from "viem";
import {
  setApiKey,
  getCoin,
  tradeCoin,
  createTradeCall,
} from "@zoralabs/coins-sdk";
import { resolveAccount, createClients } from "../lib/wallet.js";
import { getApiKey } from "../lib/config.js";
import { outputErrorAndExit } from "../lib/output.js";
import { formatEthDisplay, formatCoinsDisplay } from "../lib/format.js";
import {
  GAS_RESERVE,
  getAmountMode,
  parsePercentageLikeValue,
  getReceivedAmountFromReceipt,
  printQuote,
  printTradeResult,
} from "../lib/buy-helpers.js";

export const buyCommand = new Command("buy")
  .description("Buy a coin")
  .argument("<address>", "Coin contract address (0x…)")
  .option("--eth <value>", "Buy with ETH amount")
  .option("--percent <value>", "Buy with percentage of ETH balance")
  .option("--all", "Swap all ETH for coin")
  .option("--quote", "Print quote and exit without trading")
  .option("--yes", "Skip confirmation and execute directly")
  .option("--slippage <pct>", "Slippage tolerance percent", "1")
  .option("-o, --output <format>", "Output format: table, json", "table")
  .action(async (coinAddress: string, opts) => {
    const json = opts.output === "json";

    if (!isAddress(coinAddress)) {
      outputErrorAndExit(json, `Invalid address: ${coinAddress}`);
    }

    const output = opts.output as "table" | "json";
    if (output !== "table" && output !== "json") {
      outputErrorAndExit(
        false,
        `Invalid --output value: ${output}. Use: table, json`,
      );
    }

    const amountMode = getAmountMode(json, opts);

    const slippagePct = parsePercentageLikeValue(opts.slippage);
    if (slippagePct === undefined || slippagePct < 0 || slippagePct > 99) {
      outputErrorAndExit(
        json,
        "Invalid --slippage value. Must be between 0 and 99.",
      );
    }
    const slippage = slippagePct / 100;

    const apiKey = getApiKey();
    if (!apiKey) {
      outputErrorAndExit(
        json,
        "Not authenticated. Run 'zora auth configure' to set your API key.",
      );
    }
    setApiKey(apiKey);

    const account = resolveAccount(json);
    const { publicClient, walletClient } = createClients(account);

    let token;
    try {
      const response = await getCoin({ address: coinAddress });
      token = response.data?.zora20Token;
    } catch (err) {
      outputErrorAndExit(
        json,
        `Failed to fetch coin: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    if (!token) {
      outputErrorAndExit(json, `Coin not found: ${coinAddress}`);
    }
    const coinName = token.name;
    const coinSymbol = token.symbol;

    let amountIn: bigint;

    if (amountMode === "eth") {
      const val = parsePercentageLikeValue(opts.eth);
      if (val === undefined || val <= 0) {
        outputErrorAndExit(
          json,
          "Invalid --eth value. Must be a positive number.",
        );
      }
      try {
        amountIn = parseEther(opts.eth);
      } catch {
        outputErrorAndExit(
          json,
          "Invalid --eth value. Must be a positive number.",
        );
      }
    } else {
      const balance = await publicClient.getBalance({
        address: account.address,
      });
      if (balance === 0n) {
        outputErrorAndExit(
          json,
          `No ETH balance. Deposit ETH to ${account.address} on Base.`,
        );
      }

      if (balance <= GAS_RESERVE) {
        outputErrorAndExit(
          json,
          `Balance too low (${formatEthDisplay(balance)} ETH). Need >0.001 ETH for gas.`,
        );
      }

      const spendableBalance = balance - GAS_RESERVE;

      if (amountMode === "all") {
        amountIn = spendableBalance;
      } else {
        const pct = parsePercentageLikeValue(opts.percent);
        if (pct === undefined || pct <= 0 || pct > 100) {
          outputErrorAndExit(
            json,
            "Invalid --percent value. Must be between 0 and 100.",
          );
        }

        amountIn =
          pct === 100
            ? spendableBalance
            : (balance * BigInt(Math.round(pct * 100))) / 10000n;

        if (amountIn === 0n) {
          outputErrorAndExit(
            json,
            "Calculated amount is zero. Balance too low.",
          );
        }
      }
    }

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
        outputErrorAndExit(
          json,
          "Quote returned zero output. Amount may be too small.",
        );
      }
      amountOut = quote.quote.amountOut;
    } catch (err) {
      outputErrorAndExit(
        json,
        `Quote failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    const ethAmount = formatEthDisplay(amountIn);
    const coinsOut = formatUnits(BigInt(amountOut), 18);
    const coinsFormatted = formatCoinsDisplay(coinsOut);

    if (opts.quote) {
      printQuote(json, {
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

    if (!opts.yes) {
      printQuote(false, {
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
        process.exit(0);
      }
    }

    let receipt: Awaited<ReturnType<typeof tradeCoin>>;
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
      outputErrorAndExit(
        json,
        `Transaction failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    txHash = receipt.transactionHash;

    try {
      receivedAmountOut = getReceivedAmountFromReceipt({
        receipt,
        tokenAddress: coinAddress as Address,
        recipient: account.address,
      });
    } catch (err) {
      console.warn(
        `Warning: transaction succeeded but could not determine received amount: ${err instanceof Error ? err.message : String(err)}`,
      );
      console.warn(`Tx: ${txHash}`);
    }

    printTradeResult(json, {
      coinName,
      coinSymbol,
      address: coinAddress,
      ethAmount,
      amountIn,
      receivedAmountOut,
      txHash,
    });
  });
