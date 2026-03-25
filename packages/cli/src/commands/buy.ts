import { Command } from "commander";
import confirm from "@inquirer/confirm";
import { parseUnits, formatUnits, isAddress, type Address } from "viem";
import {
  setApiKey,
  getCoin,
  tradeCoin,
  createTradeCall,
} from "@zoralabs/coins-sdk";
import { resolveAccount, createClients } from "../lib/wallet.js";
import { getApiKey } from "../lib/config.js";
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import { formatEthDisplay, formatCoinsDisplay } from "../lib/format.js";
import {
  GAS_RESERVE,
  BUY_AMOUNT_CHECKS,
  getAmountMode,
  parsePercentageLikeValue,
  getReceivedAmountFromReceipt,
  printQuote,
  printTradeResult,
  printDebugRequest,
  printDebugResponse,
} from "../lib/trade-helpers.js";
import { BASE_TRADE_TOKENS, type TradeTokenKey } from "../lib/constants.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";
import { track, shutdownAnalytics } from "../lib/analytics.js";

export const buyCommand = new Command("buy")
  .description("Buy a coin")
  .argument("<address>", "Coin contract address (0x…)")
  .option("--eth <value>", "Buy with ETH amount")
  .option("--usd <value>", "Buy with USD equivalent (use with --token)")
  .option("--token <asset>", "Token to spend: eth, usdc, zora", "eth")
  .option("--percent <value>", "Buy with percentage of ETH balance")
  .option("--all", "Swap all ETH for coin")
  .option("--quote", "Print quote and exit without trading")
  .option("--yes", "Skip confirmation and execute directly")
  .option("--slippage <pct>", "Slippage tolerance percent", "1")
  .option("--debug", "Print full quote request/response JSON")
  .action(async function (this: Command, coinAddress: string, opts) {
    const json = getJson(this);
    const debug = opts.debug === true;

    if (!isAddress(coinAddress)) {
      outputErrorAndExit(json, `Invalid address: ${coinAddress}`);
    }

    const tokenKey = opts.token.toLowerCase() as string;
    if (!(tokenKey in BASE_TRADE_TOKENS)) {
      outputErrorAndExit(
        json,
        `Invalid --token value: ${opts.token}. Use: eth, usdc, zora`,
      );
    }
    const inputToken = BASE_TRADE_TOKENS[tokenKey as TradeTokenKey];

    const amountMode = getAmountMode(
      json,
      opts,
      BUY_AMOUNT_CHECKS,
      "--eth, --usd, --percent, or --all",
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

      let priceUsd: number;
      if (inputToken.fixedPriceUsd != null) {
        priceUsd = inputToken.fixedPriceUsd;
      } else {
        const fetched = await fetchTokenPriceUsd(inputToken.priceAddress);
        if (fetched === null) {
          outputErrorAndExit(
            json,
            `Failed to fetch ${inputToken.symbol} price.`,
          );
          return;
        }
        priceUsd = fetched;
      }

      const tokenAmount = usdVal / priceUsd;
      amountIn = parseUnits(
        tokenAmount.toFixed(inputToken.decimals),
        inputToken.decimals,
      );

      if (amountIn === 0n) {
        outputErrorAndExit(json, "Calculated amount is zero. USD too small.");
      }

      if (debug) {
        console.error(
          `[debug] $${usdVal} USD = ${formatUnits(amountIn, inputToken.decimals)} ${inputToken.symbol} (price: $${priceUsd})`,
        );
      }
    } else if (amountMode === "eth") {
      const val = parsePercentageLikeValue(opts.eth);
      if (val === undefined || val <= 0) {
        outputErrorAndExit(
          json,
          "Invalid --eth value. Must be a positive number.",
        );
      }
      try {
        amountIn = parseUnits(opts.eth, inputToken.decimals);
      } catch {
        outputErrorAndExit(
          json,
          "Invalid --eth value. Must be a positive number.",
        );
      }
    } else {
      const isEth = tokenKey === "eth";
      let balance: bigint;

      if (isEth) {
        balance = await publicClient.getBalance({
          address: account.address,
        });
      } else {
        const tokenAddress = (inputToken.trade as { address: Address }).address;
        balance = await publicClient.readContract({
          address: tokenAddress,
          abi: [
            {
              name: "balanceOf",
              type: "function",
              stateMutability: "view",
              inputs: [{ name: "account", type: "address" }],
              outputs: [{ name: "", type: "uint256" }],
            },
          ],
          functionName: "balanceOf",
          args: [account.address],
        });
      }

      if (balance === 0n) {
        outputErrorAndExit(
          json,
          `No ${inputToken.symbol} balance. Deposit ${inputToken.symbol} to ${account.address} on Base.`,
        );
      }

      const gasReserve = isEth ? GAS_RESERVE : 0n;

      if (isEth && balance <= gasReserve) {
        outputErrorAndExit(
          json,
          `Balance too low (${formatEthDisplay(balance)} ETH). Need >0.001 ETH for gas.`,
        );
      }

      const spendableBalance = balance - gasReserve;

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
            : (spendableBalance * BigInt(Math.round(pct * 100))) / 10000n;

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
      const priceUsd =
        inputToken.fixedPriceUsd ??
        (await fetchTokenPriceUsd(inputToken.priceAddress));
      if (priceUsd != null) {
        swapAmountUsd = Number(
          (
            Number(formatUnits(amountIn, inputToken.decimals)) * priceUsd
          ).toFixed(2),
        );
      }
    }

    const tradeParameters = {
      sell: inputToken.trade,
      buy: { type: "erc20" as const, address: coinAddress as Address },
      amountIn,
      slippage,
      sender: account.address,
    };

    if (debug) {
      printDebugRequest("buy", tradeParameters);
    }

    let amountOut: string;
    try {
      const quote = await createTradeCall(tradeParameters);

      if (debug) {
        printDebugResponse("buy", quote as unknown as Record<string, unknown>);
      }

      if (!quote.quote?.amountOut || quote.quote.amountOut === "0") {
        outputErrorAndExit(
          json,
          "Quote returned zero output. Amount may be too small.",
        );
      }
      amountOut = quote.quote.amountOut;
    } catch (err) {
      if (debug) {
        console.error(
          `\n[debug] buy — Quote Error:\n${err instanceof Error ? err.stack || err.message : String(err)}\n`,
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
        "Check the coin address is valid and try again. Use --debug for full error details.",
      );
    }

    const spendAmount = formatUnits(amountIn, inputToken.decimals);
    const spendFormatted = new Intl.NumberFormat("en-US", {
      maximumFractionDigits: 6,
    }).format(Number(spendAmount));
    const coinsOut = formatUnits(BigInt(amountOut), 18);
    const coinsFormatted = formatCoinsDisplay(coinsOut);

    if (opts.quote) {
      printQuote(json, {
        coinName,
        coinSymbol,
        address: coinAddress,
        spendAmount: `${spendFormatted} ${inputToken.symbol}`,
        amountIn,
        inputTokenSymbol: inputToken.symbol,
        inputTokenDecimals: inputToken.decimals,
        coinsFormatted,
        amountOut,
        slippagePct,
      });
      track("cli_buy", {
        action: "quote",
        coin_address: coinAddress,
        coin_name: coinName,
        coin_symbol: coinSymbol,
        amount_mode: amountMode,
        swap_amount_usd: swapAmountUsd,
        valueUsd: swapAmountUsd,
        swapCoinType: token.coinType ?? null,
        slippage: slippagePct,
        output_format: json ? "json" : "table",
      });
      return;
    }

    if (!opts.yes) {
      printQuote(false, {
        coinName,
        coinSymbol,
        address: coinAddress,
        spendAmount: `${spendFormatted} ${inputToken.symbol}`,
        amountIn,
        inputTokenSymbol: inputToken.symbol,
        inputTokenDecimals: inputToken.decimals,
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
      track("cli_buy", {
        action: "trade",
        coin_address: coinAddress,
        coin_name: coinName,
        coin_symbol: coinSymbol,
        amount_mode: amountMode,
        swap_amount_usd: swapAmountUsd,
        valueUsd: swapAmountUsd,
        swapCoinType,
        slippage: slippagePct,
        output_format: json ? "json" : "table",
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

    try {
      const result = getReceivedAmountFromReceipt({
        receipt,
        tokenAddress: coinAddress as Address,
        recipient: account.address,
      });
      receivedAmountOut = result.amount;
      swapLogIndex = result.logIndex;
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
      spendAmount,
      amountIn,
      inputTokenSymbol: inputToken.symbol,
      inputTokenDecimals: inputToken.decimals,
      receivedAmountOut,
      txHash,
    });

    track("cli_buy", {
      action: "trade",
      coin_address: coinAddress,
      coin_name: coinName,
      coin_symbol: coinSymbol,
      amount_mode: amountMode,
      input_amount: amountIn.toString(),
      input_token_symbol: inputToken.symbol,
      swap_amount_usd: swapAmountUsd,
      valueUsd: swapAmountUsd,
      swapCoinType,
      transactionHash: txHash,
      logIndex: swapLogIndex,
      slippage: slippagePct,
      output_format: json ? "json" : "table",
      success: true,
      tx_hash: txHash,
    });
  });
