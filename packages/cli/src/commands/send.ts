import { Command } from "commander";
import confirm from "@inquirer/confirm";
import {
  erc20Abi,
  formatUnits,
  isAddress,
  parseUnits,
  type Address,
} from "viem";
import { setApiKey } from "@zoralabs/coins-sdk";
import { resolveAccount, createClients } from "../lib/wallet.js";
import { getApiKey } from "../lib/config.js";
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import {
  parsePositionalCoinArgs,
  coinArgsToRef,
  resolveAmbiguousName,
  resolveCoin,
  formatAmbiguousError,
  CoinArgError,
} from "../lib/coin-ref.js";
import { formatAmountDisplay } from "../lib/format.js";
import {
  GAS_RESERVE,
  getAmountMode,
  parsePercentageLikeValue,
} from "../lib/trade-helpers.js";
import { track, shutdownAnalytics } from "../lib/analytics.js";
import {
  BASE_TRADE_TOKENS,
  WETH_ADDRESS,
  type TradeTokenKey,
} from "../lib/constants.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";

const SEND_AMOUNT_CHECKS = {
  amount: (opts: Record<string, unknown>) => opts.amount !== undefined,
  percent: (opts: Record<string, unknown>) => opts.percent !== undefined,
  all: (opts: Record<string, unknown>) => opts.all === true,
} as const;

const KNOWN_TOKEN_NAMES = new Set(["eth", "usdc", "zora"]);

function printSendPreview(info: {
  name: string;
  symbol: string;
  amountFormatted: string;
  amountUsd: number | null;
  to: string;
}): void {
  const usdStr =
    info.amountUsd != null ? ` ($${info.amountUsd.toFixed(2)})` : "";
  console.log(`\n Send ${info.name} (${info.symbol})\n`);
  console.log(
    `   Amount       ${info.amountFormatted} ${info.symbol}${usdStr}`,
  );
  console.log(`   To           ${info.to}`);
  console.log(`\n   Ensure receiving wallet can receive on Base.`);
  console.log("");
}

function printSendResult(
  json: boolean,
  info: {
    name: string;
    symbol: string;
    address: string | null;
    amount: bigint;
    decimals: number;
    amountFormatted: string;
    amountUsd: number | null;
    to: string;
    txHash: string;
  },
): void {
  if (json) {
    outputJson({
      action: "send",
      coin: info.symbol,
      address: info.address,
      sent: {
        amount: formatUnits(info.amount, info.decimals),
        raw: info.amount.toString(),
        symbol: info.symbol,
        amountUsd: info.amountUsd,
      },
      to: info.to,
      tx: info.txHash,
    });
    return;
  }

  const usdStr =
    info.amountUsd != null ? ` ($${info.amountUsd.toFixed(2)})` : "";
  console.log(`\n Sent ${info.name}\n`);
  console.log(
    `   Amount       ${info.amountFormatted} ${info.symbol}${usdStr}`,
  );
  console.log(`   To           ${info.to}`);
  console.log(`   Tx           ${info.txHash}\n`);
}

export const sendCommand = new Command("send")
  .description("Send coins or ETH to an address")
  .argument(
    "[typeOrId]",
    "Token (eth, usdc, zora), type prefix (creator-coin, trend), or coin address/name",
  )
  .argument("[identifier]", "Coin name (when type prefix is given)")
  .option("--to <address>", "Recipient address (0x...)")
  .option("--amount <value>", "Send specific amount")
  .option("--percent <value>", "Send percentage of balance (1-100)")
  .option("--all", "Send entire balance")
  .option("--yes", "Skip confirmation")
  .action(async function (
    this: Command,
    firstArg: string,
    secondArg: string | undefined,
    opts: {
      to?: string;
      amount?: string;
      percent?: string;
      all?: boolean;
      yes?: boolean;
    },
  ) {
    const json = getJson(this);

    if (!opts.to) {
      outputErrorAndExit(
        json,
        "Missing --to flag.",
        "Usage: zora send <identifier> --to <address>",
      );
    }

    if (!isAddress(opts.to)) {
      outputErrorAndExit(
        json,
        `Invalid recipient address: ${opts.to}`,
        "Must be a valid 0x address.",
      );
    }
    const recipient = opts.to as Address;

    const amountMode = getAmountMode(
      json,
      opts,
      SEND_AMOUNT_CHECKS,
      "--amount, --percent, or --all",
    );

    // Check known tokens first (eth, usdc, zora)
    const isKnownToken = KNOWN_TOKEN_NAMES.has(firstArg.toLowerCase());
    const isEth = firstArg.toLowerCase() === "eth";

    if (isEth) {
      const account = resolveAccount(json);
      const { publicClient, walletClient } = createClients(account);

      const balance = await publicClient.getBalance({
        address: account.address,
      });

      if (balance === 0n) {
        outputErrorAndExit(
          json,
          `No ETH balance. Deposit ETH to ${account.address} on Base.`,
        );
      }

      let amount: bigint;

      if (amountMode === "amount") {
        const val = parsePercentageLikeValue(opts.amount!);
        if (val === undefined || val <= 0) {
          outputErrorAndExit(
            json,
            "Invalid --amount value. Must be a positive number.",
          );
        }
        try {
          amount = parseUnits(opts.amount!, 18);
        } catch {
          outputErrorAndExit(
            json,
            "Invalid --amount value. Must be a valid ETH amount.",
          );
        }
        if (amount === 0n) {
          outputErrorAndExit(
            json,
            "Amount too small — rounds to zero at 18 decimal places.",
          );
        }
        if (amount + GAS_RESERVE > balance) {
          outputErrorAndExit(
            json,
            `Insufficient balance. Have ${formatAmountDisplay(balance, 18)} ETH (need to reserve ~${formatAmountDisplay(GAS_RESERVE, 18)} ETH for gas).`,
          );
        }
      } else {
        if (balance <= GAS_RESERVE) {
          outputErrorAndExit(
            json,
            `Balance too low (${formatAmountDisplay(balance, 18)} ETH). Need >${formatAmountDisplay(GAS_RESERVE, 18)} ETH for gas.`,
          );
        }

        const spendable = balance - GAS_RESERVE;

        if (amountMode === "all") {
          amount = spendable;
        } else {
          const pct = parsePercentageLikeValue(opts.percent!);
          if (pct === undefined || pct <= 0 || pct > 100) {
            outputErrorAndExit(
              json,
              "Invalid --percent value. Must be between 0 and 100.",
            );
          }
          amount =
            pct === 100
              ? spendable
              : (spendable * BigInt(Math.round(pct * 100))) / 10000n;

          if (amount === 0n) {
            outputErrorAndExit(
              json,
              "Calculated amount is zero. Balance too low.",
            );
          }
        }
      }

      const amountFormatted = formatAmountDisplay(amount, 18);

      let amountUsd: number | null = null;
      const ethPriceUsd = await fetchTokenPriceUsd(WETH_ADDRESS);
      if (ethPriceUsd != null) {
        amountUsd = Number(
          (Number(formatUnits(amount, 18)) * ethPriceUsd).toFixed(2),
        );
      }

      if (!opts.yes) {
        printSendPreview({
          name: "ETH",
          symbol: "ETH",
          amountFormatted,
          amountUsd,
          to: recipient,
        });

        const ok = await confirm({ message: "Confirm?", default: false });
        if (!ok) {
          console.error("Aborted.");
          process.exit(0);
        }
      }

      let txHash: string;
      try {
        txHash = await walletClient.sendTransaction({
          to: recipient,
          value: amount,
        });
      } catch (err) {
        track("cli_send", {
          asset: "eth",
          output_format: json ? "json" : "static",
          success: false,
          error_type: err instanceof Error ? err.constructor.name : "unknown",
        });
        await shutdownAnalytics();
        outputErrorAndExit(
          json,
          `Transaction failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }

      await publicClient.waitForTransactionReceipt({
        hash: txHash as `0x${string}`,
      });

      printSendResult(json, {
        name: "ETH",
        symbol: "ETH",
        address: null,
        amount,
        decimals: 18,
        amountFormatted,
        amountUsd,
        to: recipient,
        txHash,
      });

      track("cli_send", {
        asset: "eth",
        amount_mode: amountMode,
        amount_usd: amountUsd,
        transactionHash: txHash,
        output_format: json ? "json" : "static",
        success: true,
        tx_hash: txHash,
      });
    } else {
      // ERC-20 path: known token (usdc, zora) or coin resolution
      const knownTokenKey = firstArg.toLowerCase() as TradeTokenKey;
      const knownToken =
        isKnownToken &&
        knownTokenKey !== "eth" &&
        knownTokenKey in BASE_TRADE_TOKENS
          ? BASE_TRADE_TOKENS[knownTokenKey]
          : undefined;

      let tokenAddress: Address;
      let tokenName: string;

      if (knownToken) {
        const trade = knownToken.trade as { address: Address };
        tokenAddress = trade.address;
        tokenName = knownToken.symbol;
      } else {
        const apiKey = getApiKey();
        if (apiKey) {
          setApiKey(apiKey);
        }

        let parsed;
        try {
          parsed = parsePositionalCoinArgs(firstArg, secondArg);
        } catch (err) {
          if (err instanceof CoinArgError) {
            outputErrorAndExit(json, err.message, err.suggestion);
          }
          throw err;
        }

        if (parsed.kind === "ambiguous-name") {
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
              "send",
            );
            outputErrorAndExit(json, message, suggestion);
            return;
          }

          tokenAddress = ambResult.coin.address as Address;
          tokenName = ambResult.coin.name;
        } else {
          const ref = coinArgsToRef(parsed);
          try {
            const result = await resolveCoin(ref);
            if (result.kind === "not-found") {
              outputErrorAndExit(json, result.message, result.suggestion);
              return;
            }
            tokenAddress = result.coin.address as Address;
            tokenName = result.coin.name;
          } catch (err) {
            outputErrorAndExit(
              json,
              `Request failed: ${err instanceof Error ? err.message : String(err)}`,
            );
            return;
          }
        }
      }

      const account = resolveAccount(json);
      const { publicClient, walletClient } = createClients(account);

      let balance: bigint;
      let decimals: number;
      let symbol: string;

      if (knownToken) {
        balance = await publicClient.readContract({
          abi: erc20Abi,
          address: tokenAddress,
          functionName: "balanceOf",
          args: [account.address],
        });
        decimals = knownToken.decimals;
        symbol = knownToken.symbol;
      } else {
        const results = await Promise.all([
          publicClient.readContract({
            abi: erc20Abi,
            address: tokenAddress,
            functionName: "balanceOf",
            args: [account.address],
          }),
          publicClient.readContract({
            abi: erc20Abi,
            address: tokenAddress,
            functionName: "decimals",
          }),
          publicClient.readContract({
            abi: erc20Abi,
            address: tokenAddress,
            functionName: "symbol",
          }),
        ]);
        balance = results[0];
        decimals = results[1];
        symbol = results[2];
      }

      if (balance === 0n) {
        outputErrorAndExit(
          json,
          `No ${symbol} balance. Buy some first or pick a different wallet.`,
        );
      }

      let amount: bigint;

      if (amountMode === "amount") {
        const val = parsePercentageLikeValue(opts.amount!);
        if (val === undefined || val <= 0) {
          outputErrorAndExit(
            json,
            "Invalid --amount value. Must be a positive number.",
          );
        }
        try {
          amount = parseUnits(opts.amount!, decimals);
        } catch {
          outputErrorAndExit(
            json,
            "Invalid --amount value for token decimals.",
          );
        }
        if (amount === 0n) {
          outputErrorAndExit(
            json,
            `Amount too small — rounds to zero at ${decimals} decimal places.`,
          );
        }
        if (amount > balance) {
          outputErrorAndExit(
            json,
            `Insufficient balance. Have ${formatAmountDisplay(balance, decimals)} ${symbol}.`,
          );
        }
      } else if (amountMode === "all") {
        amount = balance;
      } else {
        const pct = parsePercentageLikeValue(opts.percent!);
        if (pct === undefined || pct <= 0 || pct > 100) {
          outputErrorAndExit(
            json,
            "Invalid --percent value. Must be between 0 and 100.",
          );
        }
        amount =
          pct === 100
            ? balance
            : (balance * BigInt(Math.round(pct * 100))) / 10000n;

        if (amount === 0n) {
          outputErrorAndExit(
            json,
            "Calculated amount is zero. Balance too low.",
          );
        }
      }

      const amountFormatted = formatAmountDisplay(amount, decimals);

      let amountUsd: number | null = null;
      const priceAddress = knownToken ? knownToken.priceAddress : tokenAddress;
      const priceUsd =
        knownToken?.fixedPriceUsd ?? (await fetchTokenPriceUsd(priceAddress));
      if (priceUsd != null) {
        amountUsd = Number(
          (Number(formatUnits(amount, decimals)) * priceUsd).toFixed(2),
        );
      }

      if (!opts.yes) {
        printSendPreview({
          name: tokenName,
          symbol,
          amountFormatted,
          amountUsd,
          to: recipient,
        });

        const ok = await confirm({ message: "Confirm?", default: false });
        if (!ok) {
          console.error("Aborted.");
          process.exit(0);
        }
      }

      let txHash: `0x${string}`;
      try {
        txHash = await walletClient.writeContract({
          abi: erc20Abi,
          address: tokenAddress,
          functionName: "transfer",
          args: [recipient, amount],
        });
      } catch (err) {
        track("cli_send", {
          asset: knownToken ? knownTokenKey : "coin",
          coin_address: tokenAddress,
          coin_name: tokenName,
          coin_symbol: symbol,
          output_format: json ? "json" : "static",
          success: false,
          error_type: err instanceof Error ? err.constructor.name : "unknown",
        });
        await shutdownAnalytics();
        outputErrorAndExit(
          json,
          `Transaction failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }

      await publicClient.waitForTransactionReceipt({ hash: txHash });

      printSendResult(json, {
        name: tokenName,
        symbol,
        address: tokenAddress,
        amount,
        decimals,
        amountFormatted,
        amountUsd,
        to: recipient,
        txHash,
      });

      track("cli_send", {
        asset: knownToken ? knownTokenKey : "coin",
        coin_address: tokenAddress,
        coin_name: tokenName,
        coin_symbol: symbol,
        amount_mode: amountMode,
        amount_usd: amountUsd,
        transactionHash: txHash,
        output_format: json ? "json" : "static",
        success: true,
        tx_hash: txHash,
      });
    }
  });
