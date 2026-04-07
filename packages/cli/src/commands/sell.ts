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
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import { safeExit, SUCCESS, ERROR } from "../lib/exit.js";
import { formatUsd } from "../lib/format.js";
import { BASE_TRADE_TOKENS, type TradeTokenKey } from "../lib/constants.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";
import { formatAmountDisplay } from "../lib/format.js";
import {
  SELL_AMOUNT_CHECKS,
  getAmountMode,
  parsePercentageLikeValue,
  getReceivedAmountFromReceipt,
  printDebugRequest,
  printDebugResponse,
} from "../lib/trade-helpers.js";
import { track, shutdownAnalytics } from "../lib/analytics.js";
import {
  parsePositionalCoinArgs,
  coinArgsToRef,
  resolveAmbiguousName,
  resolveCoin,
  formatAmbiguousError,
  CoinArgError,
  mapCoinType,
} from "../lib/coin-ref.js";
import { tradeErrorMessage, apiErrorMessage } from "../lib/errors.js";

type OutputAsset = TradeTokenKey;

function printSellQuote(
  output: "static" | "json",
  info: {
    coinName: string;
    coinSymbol: string;
    coinType: string;
    address: string;
    soldFormatted: string;
    amountIn: bigint;
    coinDecimals: number;
    receivedFormatted: string;
    quoteAmountOut: string;
    outputSymbol: string;
    outputDecimals: number;
    slippagePct: number;
    receivedUsd?: string;
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

  console.log(`\n Sell \x1b[1m${info.coinName}\x1b[0m`);
  console.log(` ${info.coinType} \u00b7 ${info.address}\n`);
  console.log(`   Amount       ${info.soldFormatted} ${info.coinSymbol}`);
  console.log(
    `   You get      ~${info.receivedFormatted} ${info.outputSymbol}${info.receivedUsd ? ` (${info.receivedUsd})` : ""}`,
  );
  console.log(`   Slippage     ${info.slippagePct}%\n`);
}

function printSellResult(
  output: "static" | "json",
  info: {
    coinName: string;
    coinSymbol: string;
    coinType: string;
    address: string;
    amountIn: bigint;
    coinDecimals: number;
    soldFormatted: string;
    receivedAmountOut: bigint;
    outputSymbol: string;
    outputDecimals: number;
    receivedSource: "receipt" | "quote";
    txHash: string;
    receivedUsd?: string;
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

  console.log(`\n Sold \x1b[1m${info.coinName}\x1b[0m`);
  console.log(` ${info.coinType} \u00b7 ${info.address}\n`);
  console.log(`   Sold         ${info.soldFormatted} ${info.coinSymbol}`);
  console.log(
    `   Received     ${info.receivedSource === "quote" ? "~" : ""}${receivedFormatted} ${info.outputSymbol}${info.receivedUsd ? ` (${info.receivedUsd})` : ""}`,
  );
  if (info.receivedSource === "quote") {
    console.log("   Note         based on quote");
  }
  console.log(`   Tx           ${info.txHash}\n`);
}

export const sellCommand = new Command("sell")
  .description("Sell a coin")
  .argument(
    "[typeOrId]",
    "Type prefix (creator-coin, trend) or coin address/name",
  )
  .argument("[identifier]", "Coin name (when type prefix is given)")
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
  .action(async function (
    this: Command,
    typeOrId: string,
    identifier: string | undefined,
    opts,
  ) {
    const json = getJson(this);
    const debug = opts.debug === true;

    let parsed;
    try {
      parsed = parsePositionalCoinArgs(typeOrId, identifier);
    } catch (err) {
      if (err instanceof CoinArgError) {
        outputErrorAndExit(json, err.message, err.suggestion);
      }
      throw err;
    }

    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

    let coinAddress: string;

    if (parsed.kind === "address") {
      if (!isAddress(parsed.address)) {
        outputErrorAndExit(json, `Invalid address: ${parsed.address}`);
        return;
      }
      coinAddress = parsed.address;
    } else if (parsed.kind === "ambiguous-name") {
      let ambResult;
      try {
        ambResult = await resolveAmbiguousName(parsed.name);
      } catch (err) {
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        );
        return;
      }

      if (ambResult.kind === "not-found") {
        outputErrorAndExit(json, ambResult.message);
        return;
      }

      if (ambResult.kind === "ambiguous") {
        const { message, suggestion } = formatAmbiguousError(
          parsed.name,
          ambResult.creator,
          ambResult.trend,
          "sell",
        );
        outputErrorAndExit(json, message, suggestion);
        return;
      }

      coinAddress = ambResult.coin.address;
    } else {
      // typed
      const ref = coinArgsToRef(parsed);
      try {
        const result = await resolveCoin(ref);
        if (result.kind === "not-found") {
          outputErrorAndExit(json, result.message, result.suggestion);
          return;
        }
        coinAddress = result.coin.address;
      } catch (err) {
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        );
        return;
      }
    }

    const output: "static" | "json" = json ? "json" : "static";

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

    const account = resolveAccount(json);
    const { publicClient, walletClient } = createClients(account);

    let token;
    try {
      const response = await getCoin({ address: coinAddress });
      token = response.data?.zora20Token;
    } catch (err) {
      outputErrorAndExit(json, `Failed to fetch coin: ${apiErrorMessage(err)}`);
    }
    if (!token) {
      outputErrorAndExit(json, `Coin not found: ${coinAddress}`);
    }

    const coinName = token.name;
    const coinSymbol = token.symbol;
    const coinType = mapCoinType(token.coinType);
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

    // Fetch coin price and output token price in parallel
    const needsCoinPrice = amountMode !== "usd";
    const needsOutputPrice = outputToken.fixedPriceUsd == null;
    const [coinPriceUsd, outputPriceUsd] = await Promise.all([
      needsCoinPrice ? fetchTokenPriceUsd(coinAddress) : Promise.resolve(null),
      needsOutputPrice
        ? fetchTokenPriceUsd(outputToken.priceAddress)
        : Promise.resolve(null),
    ]);

    let swapAmountUsd: number | undefined;
    if (amountMode === "usd") {
      swapAmountUsd = parsePercentageLikeValue(opts.usd);
    } else if (coinPriceUsd !== null && coinPriceUsd > 0) {
      swapAmountUsd = Number(
        (Number(formatUnits(amountIn, coinDecimals)) * coinPriceUsd).toFixed(2),
      );
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
          safeExit(ERROR);
        }
        outputErrorAndExit(
          json,
          "Not enough available liquidity for your swap. Please try swapping fewer tokens.",
        );
      }
      outputErrorAndExit(
        json,
        `Quote failed: ${apiErrorMessage(err)}`,
        "Check the coin address and amount, then try again. Use --debug for full error details.",
      );
    }

    const soldFormatted = formatAmountDisplay(amountIn, coinDecimals);
    const receivedFormatted = formatAmountDisplay(
      BigInt(quoteAmountOut),
      outputToken.decimals,
    );

    // USD annotation for non-stablecoin outputs
    let receivedUsd: string | undefined;
    if (outputPriceUsd != null) {
      const outAmount = Number(
        formatUnits(BigInt(quoteAmountOut), outputToken.decimals),
      );
      receivedUsd = `~${formatUsd(outAmount * outputPriceUsd)}`;
    }

    // --quote: print quote and exit
    if (opts.quote) {
      printSellQuote(output, {
        coinName,
        coinSymbol,
        coinType,
        address: coinAddress,
        soldFormatted,
        amountIn,
        coinDecimals,
        receivedFormatted,
        quoteAmountOut,
        outputSymbol: outputToken.symbol,
        outputDecimals: outputToken.decimals,
        slippagePct,
        receivedUsd,
      });
      track("cli_sell", {
        action: "quote",
        coin_address: coinAddress,
        coin_name: coinName,
        coin_symbol: coinSymbol,
        amount_mode: amountMode,
        swap_amount_usd: swapAmountUsd,
        valueUsd: swapAmountUsd,
        swapCoinType: token.coinType ?? null,
        output_asset: outputAsset,
        slippage: slippagePct,
        output_format: output,
      });
      return;
    }

    if (!opts.yes) {
      printSellQuote("static", {
        coinName,
        coinSymbol,
        coinType,
        address: coinAddress,
        soldFormatted,
        amountIn,
        coinDecimals,
        receivedFormatted,
        quoteAmountOut,
        outputSymbol: outputToken.symbol,
        outputDecimals: outputToken.decimals,
        slippagePct,
        receivedUsd,
      });

      const ok = await confirm({
        message: "Confirm?",
        default: false,
      });
      if (!ok) {
        console.error("Aborted.");
        safeExit(SUCCESS);
      }
    }

    let receipt: Awaited<ReturnType<typeof tradeCoin>>;
    let txHash: string;
    let receivedAmountOut = BigInt(quoteAmountOut);
    let receivedSource: "receipt" | "quote" = "quote";
    let swapLogIndex: number | null = null;
    const swapCoinType = token.coinType ?? null;
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
        valueUsd: swapAmountUsd,
        swapCoinType,
        output_asset: outputAsset,
        slippage: slippagePct,
        output_format: output,
        success: false,
        error_type: err instanceof Error ? err.constructor.name : "unknown",
      });
      await shutdownAnalytics();
      outputErrorAndExit(json, tradeErrorMessage(err));
    }
    txHash = receipt.transactionHash;

    // For ERC-20 outputs, try to get actual received amount from receipt
    if (outputToken.trade.type === "erc20") {
      try {
        const result = getReceivedAmountFromReceipt({
          receipt,
          tokenAddress: outputToken.trade.address,
          recipient: account.address,
        });
        receivedAmountOut = result.amount;
        swapLogIndex = result.logIndex;
        receivedSource = "receipt";
      } catch {
        // Fall back to quote amount
      }
    }

    // Recompute USD annotation from actual received amount
    if (outputPriceUsd != null) {
      const actualAmount = Number(
        formatUnits(receivedAmountOut, outputToken.decimals),
      );
      receivedUsd = `~${formatUsd(actualAmount * outputPriceUsd)}`;
    }

    printSellResult(output, {
      coinName,
      coinSymbol,
      coinType,
      address: coinAddress,
      amountIn,
      coinDecimals,
      soldFormatted,
      receivedAmountOut,
      outputSymbol: outputToken.symbol,
      outputDecimals: outputToken.decimals,
      receivedSource,
      txHash,
      receivedUsd,
    });

    track("cli_sell", {
      action: "trade",
      coin_address: coinAddress,
      coin_name: coinName,
      coin_symbol: coinSymbol,
      amount_mode: amountMode,
      swap_amount_usd: swapAmountUsd,
      valueUsd: swapAmountUsd,
      swapCoinType,
      transactionHash: txHash,
      logIndex: swapLogIndex,
      output_asset: outputAsset,
      slippage: slippagePct,
      output_format: output,
      success: true,
      tx_hash: txHash,
    });
  });
