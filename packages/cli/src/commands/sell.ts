import { Command } from "commander";
import confirm from "@inquirer/confirm";
import {
  erc20Abi,
  formatUnits,
  isAddress,
  parseUnits,
  type Address,
} from "viem";
import {
  createTradeCall,
  getCoin,
  setApiKey,
  tradeCoin,
} from "@zoralabs/coins-sdk";
import { resolveAccount, createClients } from "../lib/wallet.js";
import { getApiKey } from "../lib/config.js";
import { outputErrorAndExit, outputJson } from "../lib/output.js";
import { BASE_TRADE_TOKENS, type TradeTokenKey } from "../lib/constants.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";
import {
  SELL_AMOUNT_CHECKS,
  getAmountMode,
  parsePercentageLikeValue,
  formatAmountDisplay,
  getReceivedAmountFromReceipt,
  printDebugRequest,
  printDebugResponse,
} from "../lib/trade-helpers.js";
import { track, shutdownAnalytics } from "../lib/analytics.js";

type OutputAsset = TradeTokenKey;

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
    outputJson({
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
    outputJson({
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
  .option("--usd <value>", "Sell USD equivalent worth of coins")
  .option("--percent <value>", "Sell percentage of coin balance")
  .option("--all", "Sell entire coin balance")
  .option("--to <asset>", "Receive asset: eth, usdc, zora", "eth")
  .option("--token <asset>", "Receive asset: eth, usdc, zora (alias for --to)")
  .option("--quote", "Print quote and exit without trading")
  .option("--yes", "Skip confirmation and execute directly")
  .option("--slippage <pct>", "Slippage tolerance percent", "1")
  .option("--debug", "Print full quote request/response JSON")
  .option("-o, --output <format>", "Output format: table, json", "table")
  .action(async (coinAddress: string, opts) => {
    const json = opts.output === "json";
    const debug = opts.debug === true;

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

    // --token takes precedence over --to
    const outputAsset = (
      opts.token ? opts.token.toLowerCase() : opts.to
    ) as string;
    if (!(outputAsset in BASE_TRADE_TOKENS)) {
      outputErrorAndExit(
        json,
        `Invalid --${opts.token ? "token" : "to"} value: ${outputAsset}. Use: eth, usdc, zora`,
      );
    }
    const outputToken = BASE_TRADE_TOKENS[outputAsset as OutputAsset];

    const amountMode = getAmountMode(
      json,
      opts,
      SELL_AMOUNT_CHECKS,
      "--amount, --usd, --percent, or --all",
    );

    const slippagePct = parsePercentageLikeValue(opts.slippage);
    if (slippagePct === undefined || slippagePct < 0 || slippagePct > 99) {
      outputErrorAndExit(
        json,
        "Invalid --slippage value. Must be between 0 and 99.",
      );
    }
    const slippage = slippagePct / 100;

    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

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
    const coinDecimals = Number(token.decimals ?? 18);

    let amountIn: bigint;

    if (amountMode === "usd") {
      const usdVal = parsePercentageLikeValue(opts.usd);
      if (usdVal === undefined || usdVal <= 0) {
        outputErrorAndExit(
          json,
          "Invalid --usd value. Must be a positive number.",
        );
        return;
      }

      const coinPriceUsd = await fetchTokenPriceUsd(coinAddress);
      if (coinPriceUsd === null || coinPriceUsd <= 0) {
        outputErrorAndExit(
          json,
          `Failed to fetch ${coinSymbol} price for USD conversion.`,
        );
        return;
      }

      const coinAmount = usdVal / coinPriceUsd;
      amountIn = parseUnits(coinAmount.toFixed(coinDecimals), coinDecimals);

      if (amountIn === 0n) {
        outputErrorAndExit(json, "Calculated amount is zero. USD too small.");
      }

      if (debug) {
        console.error(
          `[debug] $${usdVal} USD = ${formatUnits(amountIn, coinDecimals)} ${coinSymbol} (coin price: $${coinPriceUsd})`,
        );
      }
    } else if (amountMode === "amount") {
      const val = parsePercentageLikeValue(opts.amount);
      if (val === undefined || val <= 0) {
        outputErrorAndExit(
          json,
          "Invalid --amount value. Must be a positive number.",
        );
      }
      try {
        amountIn = parseUnits(opts.amount, coinDecimals);
      } catch {
        outputErrorAndExit(json, "Invalid --amount value for token decimals.");
      }
    } else {
      const balance = await publicClient.readContract({
        abi: erc20Abi,
        address: coinAddress as Address,
        functionName: "balanceOf",
        args: [account.address],
      });

      if (balance === 0n) {
        outputErrorAndExit(
          json,
          `No ${coinSymbol} balance. Buy some first or pick a different wallet.`,
        );
      }

      if (amountMode === "all") {
        amountIn = balance;
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
            ? balance
            : (balance * BigInt(Math.round(pct * 100))) / 10000n;

        if (amountIn === 0n) {
          outputErrorAndExit(
            json,
            "Calculated amount is zero. Balance too low.",
          );
        }
      }
    }

    let swapAmountUsd: number | undefined;
    if (amountMode === "usd") {
      swapAmountUsd = parsePercentageLikeValue(opts.usd);
    } else {
      const coinPriceUsd = await fetchTokenPriceUsd(coinAddress);
      if (coinPriceUsd !== null && coinPriceUsd > 0) {
        swapAmountUsd = Number(
          (Number(formatUnits(amountIn, coinDecimals)) * coinPriceUsd).toFixed(
            2,
          ),
        );
      }
    }

    const tradeParameters = {
      sell: { type: "erc20" as const, address: coinAddress as Address },
      buy: outputToken.trade,
      amountIn,
      slippage,
      sender: account.address,
    };

    if (debug) {
      printDebugRequest("sell", tradeParameters);
    }

    let quoteAmountOut: string;
    try {
      const quote = await createTradeCall(tradeParameters);

      if (debug) {
        printDebugResponse("sell", quote as unknown as Record<string, unknown>);
      }

      if (!quote.quote?.amountOut || quote.quote.amountOut === "0") {
        outputErrorAndExit(
          json,
          "Quote returned zero output. Amount may be too small.",
        );
      }
      quoteAmountOut = quote.quote.amountOut;
    } catch (err) {
      if (debug) {
        console.error(
          `\n[debug] sell — Quote Error:\n${err instanceof Error ? err.stack || err.message : String(err)}\n`,
        );
      }
      const msg = err instanceof Error ? err.message : String(err);
      const errorType = (err as any)?.errorType;
      const errorBody = (err as any)?.errorBody;
      if (errorType === "LIQUIDITY" || msg.includes("Not enough liquidity")) {
        if (json) {
          outputJson({ error: errorBody ?? msg });
          process.exit(1);
        }
        outputErrorAndExit(
          json,
          "Not enough available liquidity for your swap. Please try swapping fewer tokens.",
        );
      }
      outputErrorAndExit(
        json,
        `Quote failed: ${msg}`,
        "Check the coin address and amount, then try again. Use --debug for full error details.",
      );
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
      track("cli_sell", {
        action: "quote",
        coin_address: coinAddress,
        coin_name: coinName,
        coin_symbol: coinSymbol,
        amount_mode: amountMode,
        swap_amount_usd: swapAmountUsd,
        output_asset: outputAsset,
        slippage: slippagePct,
        output_format: output,
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

    let receipt: Awaited<ReturnType<typeof tradeCoin>>;
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
      track("cli_sell", {
        action: "trade",
        coin_address: coinAddress,
        coin_name: coinName,
        coin_symbol: coinSymbol,
        amount_mode: amountMode,
        swap_amount_usd: swapAmountUsd,
        output_asset: outputAsset,
        slippage: slippagePct,
        output_format: output,
        success: false,
        error_type: err instanceof Error ? err.constructor.name : "unknown",
      });
      await shutdownAnalytics();
      outputErrorAndExit(
        json,
        `Transaction failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    txHash = receipt.transactionHash;

    // For ERC-20 outputs, try to get actual received amount from receipt
    if (outputToken.trade.type === "erc20") {
      try {
        receivedAmountOut = getReceivedAmountFromReceipt({
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

    track("cli_sell", {
      action: "trade",
      coin_address: coinAddress,
      coin_name: coinName,
      coin_symbol: coinSymbol,
      amount_mode: amountMode,
      swap_amount_usd: swapAmountUsd,
      output_asset: outputAsset,
      slippage: slippagePct,
      output_format: output,
      success: true,
      tx_hash: txHash,
    });
  });
