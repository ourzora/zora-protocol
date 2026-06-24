import confirm from "@inquirer/confirm";
import {
  createQuote,
  getCoin,
  setApiKey,
  tradeCoin,
  tradeCoinSmartWallet,
} from "@zoralabs/coins-sdk";
import { Command } from "commander";
import { formatUnits, isAddress, parseUnits, type Address } from "viem";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import {
  CoinArgError,
  coinArgsToRef,
  formatAmbiguousError,
  mapCoinType,
  parsePositionalCoinArgs,
  resolveAmbiguousName,
  resolveCoin,
} from "../lib/coin-ref.js";
import { getApiKey, getBudget, saveBudget } from "../lib/config.js";
import { evaluate, appendSpend } from "../lib/agent/budget.js";
import { BASE_TRADE_TOKENS, type TradeTokenKey } from "../lib/constants.js";
import {
  apiErrorMessage,
  bannedCoinBuyMessage,
  serializeError,
  tradeErrorMessage,
} from "../lib/errors.js";
import { ERROR, safeExit, SUCCESS } from "../lib/exit.js";
import { formatAmountDisplay, formatUsd } from "../lib/format.js";
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import {
  BUY_AMOUNT_CHECKS,
  GAS_RESERVE,
  estimateSmartWalletGasReserve,
  getAmountMode,
  getReceivedAmountFromReceipt,
  parsePercentageLikeValue,
  printDebugRequest,
  printDebugResponse,
  printQuote,
  printTradeResult,
} from "../lib/trade-helpers.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";
import { gasErrorSuggestion } from "../lib/gas.js";

export const buyCommand = new Command("buy")
  .description("Buy a coin")
  .argument(
    "[typeOrId]",
    "Type prefix (creator-coin, trend) or coin address/name",
  )
  .argument("[identifier]", "Coin name (when type prefix is given)")
  .option("--eth <value>", "Buy with ETH amount")
  .option("--usd <value>", "Buy with USD equivalent (use with --token)")
  .option("--token <asset>", "Token to spend: eth, usdc, zora", "eth")
  .option("--percent <value>", "Buy with percentage of ETH balance")
  .option("--all", "Swap all ETH for coin")
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
        return outputErrorAndExit(json, `Invalid address: ${parsed.address}`);
      }
      coinAddress = parsed.address;
    } else if (parsed.kind === "ambiguous-name") {
      let ambResult;
      try {
        ambResult = await resolveAmbiguousName(parsed.name);
      } catch (err) {
        return outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }

      if (ambResult.kind === "not-found") {
        return outputErrorAndExit(json, ambResult.message);
      }

      if (ambResult.kind === "ambiguous") {
        const { message, suggestion } = formatAmbiguousError(
          parsed.name,
          ambResult.creator,
          ambResult.trend,
          "buy",
        );
        return outputErrorAndExit(json, message, suggestion);
      }

      coinAddress = ambResult.coin.address;
    } else {
      // typed
      const ref = coinArgsToRef(parsed);
      try {
        const result = await resolveCoin(ref);
        if (result.kind === "not-found") {
          return outputErrorAndExit(json, result.message, result.suggestion);
        }
        coinAddress = result.coin.address;
      } catch (err) {
        return outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }

    const tokenKey = opts.token.toLowerCase() as string;
    if (!(tokenKey in BASE_TRADE_TOKENS)) {
      return outputErrorAndExit(
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
      return outputErrorAndExit(
        json,
        "Invalid --slippage value. Must be between 0 and 99.",
      );
    }
    const slippage = slippagePct / 100;

    const { privateKeyAccount, smartWalletAccount } = await resolveAccounts();
    const { publicClient, walletClient, bundlerClient } = createClients(
      privateKeyAccount,
      smartWalletAccount,
    );

    const walletAddress =
      smartWalletAccount?.address ?? privateKeyAccount.address;

    let token;
    try {
      const response = await getCoin({ address: coinAddress });
      token = response.data?.zora20Token;
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Failed to fetch coin: ${apiErrorMessage(err)}`,
      );
    }
    if (!token) {
      return outputErrorAndExit(json, `Coin not found: ${coinAddress}`);
    }
    if (token.platformBlocked) {
      return outputErrorAndExit(json, bannedCoinBuyMessage(coinAddress));
    }
    const coinName = token.name;
    const coinSymbol = token.symbol;
    const coinType = mapCoinType(token.coinType);

    let amountIn: bigint;

    if (amountMode === "usd") {
      const usdVal = parsePercentageLikeValue(opts.usd);
      if (usdVal === undefined || usdVal <= 0) {
        return outputErrorAndExit(
          json,
          "Invalid --usd value. Must be a positive number.",
        );
      }

      let priceUsd: number;
      if (inputToken.fixedPriceUsd != null) {
        priceUsd = inputToken.fixedPriceUsd;
      } else {
        const fetched = await fetchTokenPriceUsd(inputToken.priceAddress);
        if (fetched === null) {
          return outputErrorAndExit(
            json,
            `Failed to fetch ${inputToken.symbol} price.`,
          );
        }
        priceUsd = fetched;
      }

      const tokenAmount = usdVal / priceUsd;
      amountIn = parseUnits(
        tokenAmount.toFixed(inputToken.decimals),
        inputToken.decimals,
      );

      if (amountIn === 0n) {
        return outputErrorAndExit(
          json,
          "Calculated amount is zero. USD too small.",
        );
      }

      if (debug) {
        console.error(
          `[debug] $${usdVal} USD = ${formatUnits(amountIn, inputToken.decimals)} ${inputToken.symbol} (price: $${priceUsd})`,
        );
      }
    } else if (amountMode === "eth") {
      const val = parsePercentageLikeValue(opts.eth);
      if (val === undefined || val <= 0) {
        return outputErrorAndExit(
          json,
          "Invalid --eth value. Must be a positive number.",
        );
      }
      try {
        amountIn = parseUnits(opts.eth, inputToken.decimals);
      } catch {
        return outputErrorAndExit(
          json,
          "Invalid --eth value. Must be a positive number.",
        );
      }
    } else {
      const isEth = tokenKey === "eth";
      let balance: bigint;

      if (isEth) {
        balance = await publicClient.getBalance({
          address: walletAddress,
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
          args: [walletAddress],
        });
      }

      if (balance === 0n) {
        return outputErrorAndExit(
          json,
          `No ${inputToken.symbol} balance. Deposit ${inputToken.symbol} to ${walletAddress} on Base.`,
        );
      }

      // A smart wallet pays gas from its own ETH via the user-operation
      // prefund, so it must reserve more than the EOA's fixed GAS_RESERVE.
      const gasReserve = isEth
        ? smartWalletAccount
          ? await estimateSmartWalletGasReserve(publicClient, "swap")
          : GAS_RESERVE
        : 0n;

      if (isEth && balance <= gasReserve) {
        return outputErrorAndExit(
          json,
          `Balance too low (${formatAmountDisplay(balance, 18)} ETH). Need >${formatAmountDisplay(gasReserve, 18)} ETH for gas.`,
        );
      }

      const spendableBalance = balance - gasReserve;

      if (amountMode === "all") {
        amountIn = spendableBalance;
      } else {
        const pct = parsePercentageLikeValue(opts.percent);
        if (pct === undefined || pct <= 0 || pct > 100) {
          return outputErrorAndExit(
            json,
            "Invalid --percent value. Must be between 0 and 100.",
          );
        }

        amountIn =
          pct === 100
            ? spendableBalance
            : (spendableBalance * BigInt(Math.round(pct * 100))) / 10000n;

        if (amountIn === 0n) {
          return outputErrorAndExit(
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
      sender: walletAddress,
    };

    if (debug) {
      printDebugRequest("buy", tradeParameters);
    }

    let amountOut: string;
    try {
      const quote = await createQuote(tradeParameters);

      if (debug) {
        printDebugResponse("buy", quote as unknown as Record<string, unknown>);
      }

      if (!quote.quote?.amountOut || quote.quote.amountOut === "0") {
        return outputErrorAndExit(
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
          return safeExit(ERROR);
        }
        return outputErrorAndExit(
          json,
          "Not enough available liquidity for your swap. Please try swapping fewer tokens.",
        );
      }
      return outputErrorAndExit(
        json,
        `Quote failed: ${apiErrorMessage(err)}`,
        "Check the coin address is valid and try again. Use --debug for full error details.",
      );
    }

    const quoteInfo = {
      coinName,
      coinSymbol,
      coinType,
      address: coinAddress,
      amountIn,
      inputTokenSymbol: inputToken.symbol,
      inputTokenDecimals: inputToken.decimals,
      amountOut,
      slippagePct,
    };

    // USD annotation for non-stablecoin inputs
    const amountUsd =
      swapAmountUsd != null && inputToken.fixedPriceUsd == null
        ? `${amountMode === "usd" ? "" : "~"}${formatUsd(swapAmountUsd)}`
        : undefined;

    if (opts.quote) {
      printQuote(json, { ...quoteInfo, amountUsd });
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
        output_format: json ? "json" : "static",
      });
      return;
    }

    if (!opts.yes) {
      printQuote(false, { ...quoteInfo, amountUsd });

      const ok = await confirm({
        message: "Confirm?",
        default: false,
      });
      if (!ok) {
        safeExit(SUCCESS);
      }
    }

    // ── Budget enforcement ──────────────────────────────────────────
    const budget = getBudget();
    if (
      budget &&
      !budget.optedOut &&
      budget.limitUsd !== null &&
      swapAmountUsd != null
    ) {
      const now = new Date();
      const evaluation = evaluate(budget, swapAmountUsd, now);
      if (!evaluation.allowed) {
        track("cli_buy", {
          action: "budget_blocked",
          coin_address: coinAddress,
          swap_amount_usd: swapAmountUsd,
          budget_limit: evaluation.limitUsd,
          budget_spent: evaluation.spent,
          budget_remaining: evaluation.remaining,
        });
        return outputErrorAndExit(
          json,
          evaluation.reason!,
          "Adjust your budget: zora agent budget set <amount> | zora agent budget reset | zora agent budget set --no-limit",
        );
      }
    }
    // ────────────────────────────────────────────────────────────────

    if (!!smartWalletAccount && !bundlerClient) {
      return outputErrorAndExit(
        json,
        "Failed to obtain bundler client for your smart wallet. Please try again. If the problem persists, ensure your smart wallet is setup correctly.",
      );
    }

    // let receipt: Awaited<ReturnType<typeof tradeCoin>>;
    let receipt: Awaited<
      ReturnType<typeof tradeCoinSmartWallet | typeof tradeCoin>
    >;
    let txHash: string;
    let receivedAmountOut = BigInt(amountOut);
    let swapLogIndex: number | null = null;
    const swapCoinType = token.coinType ?? null;
    try {
      receipt = !!smartWalletAccount
        ? await tradeCoinSmartWallet({
            tradeParameters,
            bundlerClient: bundlerClient!,
            publicClient,
            account: smartWalletAccount,
          })
        : await tradeCoin({
            tradeParameters,
            walletClient,
            publicClient,
            account: privateKeyAccount,
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
        output_format: json ? "json" : "static",
        success: false,
        error_type: err instanceof Error ? err.constructor.name : "unknown",
        error: serializeError(err),
      });
      await shutdownAnalytics();
      return outputErrorAndExit(
        json,
        tradeErrorMessage(err),
        gasErrorSuggestion(err, smartWalletAccount ?? privateKeyAccount),
      );
    }

    txHash = receipt.transactionHash;

    try {
      const result = getReceivedAmountFromReceipt({
        receipt,
        tokenAddress: coinAddress as Address,
        recipient: walletAddress,
      });
      receivedAmountOut = result.amount;
      swapLogIndex = result.logIndex;
    } catch (err) {
      console.warn(
        `Warning: transaction succeeded but could not determine received amount: ${err instanceof Error ? err.message : String(err)}`,
      );
      console.warn(`Tx: ${txHash}`);
    }

    // ── Record spend in budget ledger ───────────────────────────────
    if (budget && !budget.optedOut && swapAmountUsd != null) {
      const now = new Date();
      const updated = appendSpend(
        budget,
        {
          at: now.toISOString(),
          usd: swapAmountUsd,
          skill: `buy ${coinSymbol}`,
        },
        now,
      );
      saveBudget(updated);
    }
    // ────────────────────────────────────────────────────────────────

    printTradeResult(json, {
      coinName,
      coinSymbol,
      coinType,
      address: coinAddress,
      amountUsd,
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
      output_format: json ? "json" : "static",
      success: true,
      tx_hash: txHash,
    });
  });
