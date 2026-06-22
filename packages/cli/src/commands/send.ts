import confirm from "@inquirer/confirm";
import {
  getProfile,
  prepareUserOperation,
  setApiKey,
  submitUserOperation,
  toGenericCall,
  toUserOperationCalls,
  type ContractCall,
  type SendCall,
} from "@zoralabs/coins-sdk";
import { Command } from "commander";
import {
  erc20Abi,
  formatUnits,
  isAddress,
  parseUnits,
  type Address,
} from "viem";
import type { BundlerClient, SmartAccount } from "viem/account-abstraction";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import {
  CoinArgError,
  coinArgsToRef,
  formatAmbiguousError,
  parsePositionalCoinArgs,
  resolveAmbiguousName,
  resolveCoin,
} from "../lib/coin-ref.js";
import { getApiKey, getBudget, saveBudget } from "../lib/config.js";
import { evaluate, appendSpend } from "../lib/agent/budget.js";
import {
  BASE_TRADE_TOKENS,
  WETH_ADDRESS,
  type TradeTokenKey,
} from "../lib/constants.js";
import { bannedProfileMessage, serializeError } from "../lib/errors.js";
import { safeExit, SUCCESS } from "../lib/exit.js";
import { formatAmountDisplay } from "../lib/format.js";
import { gasErrorSuggestion } from "../lib/gas.js";
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import {
  estimateSmartWalletGasReserve,
  GAS_RESERVE,
  getAmountMode,
  parsePercentageLikeValue,
} from "../lib/trade-helpers.js";
import { fetchTokenPriceUsd } from "../lib/wallet-balances.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";

const SEND_AMOUNT_CHECKS = {
  amount: (opts: Record<string, unknown>) => opts.amount !== undefined,
  percent: (opts: Record<string, unknown>) => opts.percent !== undefined,
  all: (opts: Record<string, unknown>) => opts.all === true,
} as const;

const KNOWN_TOKEN_NAMES = new Set(["eth", "usdc", "zora"]);

type ResolvedRecipient = {
  address: Address;
  handle?: string;
  username?: string;
  displayName?: string;
  platformBlocked?: boolean;
};

/**
 * A non-empty, non-placeholder profile name. When a profile lookup misses, the
 * API returns the truncated wallet address as the `handle` (e.g. "0x1234…5678"),
 * which we don't want to surface as if it were a real profile name.
 */
function isPlaceholderName(name: string): boolean {
  return name.startsWith("0x") || name.includes("…") || name.includes("...");
}

/**
 * Resolves the `--to` argument to a recipient address. Accepts either a 0x
 * address (with a best-effort profile-name reverse lookup) or a Zora profile
 * identifier (resolved to its preferred public wallet address). Exits with an
 * error if a profile identifier can't be resolved to a wallet.
 */
async function resolveRecipient(
  identifier: string,
  json = false,
): Promise<ResolvedRecipient> {
  const isIdentifierAddress = isAddress(identifier);

  try {
    const response = await getProfile({ identifier });
    const profile = response?.data?.profile;
    const address = isIdentifierAddress
      ? (identifier as Address)
      : profile?.publicWallet?.walletAddress;
    if (!address || !isAddress(address)) {
      return outputErrorAndExit(
        json,
        !address
          ? `No Zora profile or wallet found for "${identifier}".`
          : "Provide a valid 0x address or an existing Zora profile name.",
      );
    }
    return {
      address: address,
      handle:
        profile?.handle && !isPlaceholderName(profile.handle)
          ? `@${profile.handle}`
          : undefined,
      username:
        profile?.username && !isPlaceholderName(profile.username)
          ? profile.username
          : undefined,
      displayName:
        profile?.displayName && !isPlaceholderName(profile.displayName)
          ? profile.displayName
          : undefined,
      platformBlocked: profile?.platformBlocked ?? false,
    };
  } catch (err) {
    return isIdentifierAddress
      ? { address: identifier as Address }
      : outputErrorAndExit(
          json,
          `Failed to resolve profile "${identifier}": ${err instanceof Error ? err.message : String(err)}`,
          "Make sure to provide a valid 0x address or an existing Zora profile name and try again.",
        );
  }
}

function printRecipient(recipient: ResolvedRecipient): void {
  console.log(`   To           ${recipient.address}`);
  if (recipient.handle) {
    console.log(`   Handle       ${recipient.handle}`);
  } else if (recipient.username) {
    console.log(`   Username     ${recipient.username}`);
  } else if (recipient.displayName) {
    console.log(`   Display Name ${recipient.displayName}`);
  }
}

function printSendPreview(info: {
  name: string;
  symbol: string;
  amountFormatted: string;
  amountUsd: number | null;
  recipient: ResolvedRecipient;
}): void {
  const usdStr =
    info.amountUsd != null ? ` ($${info.amountUsd.toFixed(2)})` : "";
  console.log(`\n Send ${info.name} (${info.symbol})\n`);
  console.log(
    `   Amount       ${info.amountFormatted} ${info.symbol}${usdStr}`,
  );

  printRecipient(info.recipient);

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
    recipient: ResolvedRecipient;
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
      to: info.recipient.address,
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

  printRecipient(info.recipient);

  console.log(`   Tx           ${info.txHash}\n`);
}

/**
 * Sends a single call (ETH transfer or ERC-20 transfer) from a smart wallet by
 * batching it into a user operation, mirroring the EOA path's single
 * transaction. Returns the settled transaction hash.
 */
async function sendCallViaSmartWallet(
  call: ContractCall | SendCall,
  bundlerClient: BundlerClient,
  account: SmartAccount,
): Promise<`0x${string}`> {
  const userOperation = await prepareUserOperation({
    bundlerClient,
    account,
    calls: toUserOperationCalls([toGenericCall(call)]),
  });

  const receipt = await submitUserOperation({
    bundlerClient,
    account,
    userOperation,
  });

  if (!receipt.success) {
    throw new Error(
      `User operation reverted${receipt.reason ? `: ${receipt.reason}` : ""}`,
    );
  }

  return receipt.receipt.transactionHash;
}

export const sendCommand = new Command("send")
  .description("Send coins or ETH to an address or Zora profile")
  .argument(
    "[typeOrId]",
    "Token (eth, usdc, zora), type prefix (creator-coin, trend), or coin address/name",
  )
  .argument("[identifier]", "Coin name (when type prefix is given)")
  .option("--to <recipient>", "Recipient: address (0x...) or Zora profile name")
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
      return outputErrorAndExit(
        json,
        "Missing --to flag.",
        "Usage: zora send <identifier> --to <address|profile>",
      );
    }

    // The API key (when set) raises rate limits for the profile lookups below.
    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

    const resolvedRecipient = await resolveRecipient(opts.to, json);

    // Block interaction with platform-banned profiles
    if (resolvedRecipient.platformBlocked) {
      track("cli_send", {
        output_format: json ? "json" : "text",
        success: false,
        blocked_profile: true,
      });
      return outputErrorAndExit(
        json,
        bannedProfileMessage(
          resolvedRecipient.handle ?? resolvedRecipient.address,
        ),
      );
    }

    const amountMode = getAmountMode(
      json,
      opts,
      SEND_AMOUNT_CHECKS,
      "--amount, --percent, or --all",
    );

    const { privateKeyAccount, smartWalletAccount } = await resolveAccounts();
    const { publicClient, walletClient, bundlerClient } = createClients(
      privateKeyAccount,
      smartWalletAccount,
    );

    if (!!smartWalletAccount && !bundlerClient) {
      return outputErrorAndExit(
        json,
        "Failed to obtain bundler client for your smart wallet. Please try again. If the problem persists, ensure your smart wallet is setup correctly.",
      );
    }

    const walletAddress =
      smartWalletAccount?.address ?? privateKeyAccount.address;

    // Check known tokens first (eth, usdc, zora)
    const isKnownToken = KNOWN_TOKEN_NAMES.has(firstArg.toLowerCase());
    const isEth = firstArg.toLowerCase() === "eth";

    if (isEth) {
      const balance = await publicClient.getBalance({
        address: walletAddress,
      });

      if (balance === 0n) {
        return outputErrorAndExit(
          json,
          `No ETH balance. Deposit ETH to ${walletAddress} on Base.`,
        );
      }

      // A smart wallet pays gas from its own ETH via the user-operation
      // prefund, so it must reserve more than the EOA's fixed GAS_RESERVE.
      const gasReserve = smartWalletAccount
        ? await estimateSmartWalletGasReserve(publicClient, "transfer")
        : GAS_RESERVE;

      let amount: bigint;

      if (amountMode === "amount") {
        const val = parsePercentageLikeValue(opts.amount!);
        if (val === undefined || val <= 0) {
          return outputErrorAndExit(
            json,
            "Invalid --amount value. Must be a positive number.",
          );
        }
        try {
          amount = parseUnits(opts.amount!, 18);
        } catch {
          return outputErrorAndExit(
            json,
            "Invalid --amount value. Must be a valid ETH amount.",
          );
        }
        if (amount === 0n) {
          return outputErrorAndExit(
            json,
            "Amount too small — rounds to zero at 18 decimal places.",
          );
        }
        if (amount + gasReserve > balance) {
          return outputErrorAndExit(
            json,
            `Insufficient balance. Have ${formatAmountDisplay(balance, 18)} ETH (need to reserve ~${formatAmountDisplay(gasReserve, 18)} ETH for gas).`,
          );
        }
      } else {
        if (balance <= gasReserve) {
          return outputErrorAndExit(
            json,
            `Balance too low (${formatAmountDisplay(balance, 18)} ETH). Need >${formatAmountDisplay(gasReserve, 18)} ETH for gas.`,
          );
        }

        const spendable = balance - gasReserve;

        if (amountMode === "all") {
          amount = spendable;
        } else {
          const pct = parsePercentageLikeValue(opts.percent!);
          if (pct === undefined || pct <= 0 || pct > 100) {
            return outputErrorAndExit(
              json,
              "Invalid --percent value. Must be between 0 and 100.",
            );
          }
          amount =
            pct === 100
              ? spendable
              : (spendable * BigInt(Math.round(pct * 100))) / 10000n;

          if (amount === 0n) {
            return outputErrorAndExit(
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
          recipient: resolvedRecipient,
        });

        const ok = await confirm({ message: "Confirm?", default: false });
        if (!ok) {
          console.error("Aborted.");
          return safeExit(SUCCESS);
        }
      }

      // ── Budget enforcement ──────────────────────────────────────────
      const budget = getBudget();
      if (
        budget &&
        !budget.optedOut &&
        budget.limitUsd !== null &&
        amountUsd != null
      ) {
        const now = new Date();
        const evaluation = evaluate(budget, amountUsd, now);
        if (!evaluation.allowed) {
          track("cli_send", {
            action: "budget_blocked",
            asset: "eth",
            amount_usd: amountUsd,
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

      let txHash: string;
      try {
        txHash = smartWalletAccount
          ? await sendCallViaSmartWallet(
              { to: resolvedRecipient.address, value: amount },
              bundlerClient!,
              smartWalletAccount,
            )
          : await walletClient.sendTransaction({
              to: resolvedRecipient.address,
              value: amount,
            });
      } catch (err) {
        track("cli_send", {
          asset: "eth",
          output_format: json ? "json" : "static",
          success: false,
          error_type: err instanceof Error ? err.constructor.name : "unknown",
          error: serializeError(err),
        });
        await shutdownAnalytics();
        return outputErrorAndExit(
          json,
          `Transaction failed: ${err instanceof Error ? err.message : String(err)}`,
          gasErrorSuggestion(err, smartWalletAccount ?? privateKeyAccount),
        );
      }

      // Smart wallet sends settle inside the user operation; only EOA
      // transactions need an explicit receipt wait.
      if (!smartWalletAccount) {
        await publicClient.waitForTransactionReceipt({
          hash: txHash as `0x${string}`,
        });
      }

      // ── Record spend in budget ledger ───────────────────────────────
      if (budget && !budget.optedOut && amountUsd != null) {
        const now = new Date();
        const updated = appendSpend(
          budget,
          {
            at: now.toISOString(),
            usd: amountUsd,
            skill: `send ETH to ${resolvedRecipient.address.slice(0, 10)}...`,
          },
          now,
        );
        saveBudget(updated);
      }
      // ────────────────────────────────────────────────────────────────

      printSendResult(json, {
        name: "ETH",
        symbol: "ETH",
        address: null,
        amount,
        decimals: 18,
        amountFormatted,
        amountUsd,
        recipient: resolvedRecipient,
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
        let parsed;
        try {
          parsed = parsePositionalCoinArgs(firstArg, secondArg);
        } catch (err) {
          if (err instanceof CoinArgError) {
            return outputErrorAndExit(json, err.message, err.suggestion);
          }
          throw err;
        }

        if (parsed.kind === "ambiguous-name") {
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
              "send",
            );
            return outputErrorAndExit(json, message, suggestion);
          }

          tokenAddress = ambResult.coin.address as Address;
          tokenName = ambResult.coin.name;
        } else {
          const ref = coinArgsToRef(parsed);
          try {
            const result = await resolveCoin(ref);
            if (result.kind === "not-found") {
              return outputErrorAndExit(
                json,
                result.message,
                result.suggestion,
              );
            }
            tokenAddress = result.coin.address as Address;
            tokenName = result.coin.name;
          } catch (err) {
            return outputErrorAndExit(
              json,
              `Request failed: ${err instanceof Error ? err.message : String(err)}`,
            );
          }
        }
      }

      let balance: bigint;
      let decimals: number;
      let symbol: string;

      if (knownToken) {
        balance = await publicClient.readContract({
          abi: erc20Abi,
          address: tokenAddress,
          functionName: "balanceOf",
          args: [walletAddress],
        });
        decimals = knownToken.decimals;
        symbol = knownToken.symbol;
      } else {
        const results = await Promise.all([
          publicClient.readContract({
            abi: erc20Abi,
            address: tokenAddress,
            functionName: "balanceOf",
            args: [walletAddress],
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
        return outputErrorAndExit(
          json,
          `No ${symbol} balance. Buy some first or pick a different wallet.`,
        );
      }

      let amount: bigint;

      if (amountMode === "amount") {
        const val = parsePercentageLikeValue(opts.amount!);
        if (val === undefined || val <= 0) {
          return outputErrorAndExit(
            json,
            "Invalid --amount value. Must be a positive number.",
          );
        }
        try {
          amount = parseUnits(opts.amount!, decimals);
        } catch {
          return outputErrorAndExit(
            json,
            "Invalid --amount value for token decimals.",
          );
        }
        if (amount === 0n) {
          return outputErrorAndExit(
            json,
            `Amount too small — rounds to zero at ${decimals} decimal places.`,
          );
        }
        if (amount > balance) {
          return outputErrorAndExit(
            json,
            `Insufficient balance. Have ${formatAmountDisplay(balance, decimals)} ${symbol}.`,
          );
        }
      } else if (amountMode === "all") {
        amount = balance;
      } else {
        const pct = parsePercentageLikeValue(opts.percent!);
        if (pct === undefined || pct <= 0 || pct > 100) {
          return outputErrorAndExit(
            json,
            "Invalid --percent value. Must be between 0 and 100.",
          );
        }
        amount =
          pct === 100
            ? balance
            : (balance * BigInt(Math.round(pct * 100))) / 10000n;

        if (amount === 0n) {
          return outputErrorAndExit(
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
          recipient: resolvedRecipient,
        });

        const ok = await confirm({ message: "Confirm?", default: false });
        if (!ok) {
          console.error("Aborted.");
          return safeExit(SUCCESS);
        }
      }

      // ── Budget enforcement ──────────────────────────────────────────
      const budget = getBudget();
      if (
        budget &&
        !budget.optedOut &&
        budget.limitUsd !== null &&
        amountUsd != null
      ) {
        const now = new Date();
        const evaluation = evaluate(budget, amountUsd, now);
        if (!evaluation.allowed) {
          track("cli_send", {
            action: "budget_blocked",
            asset: knownToken ? knownTokenKey : "coin",
            coin_address: tokenAddress,
            amount_usd: amountUsd,
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

      let txHash: `0x${string}`;
      try {
        txHash = smartWalletAccount
          ? await sendCallViaSmartWallet(
              {
                abi: erc20Abi,
                address: tokenAddress,
                functionName: "transfer",
                args: [resolvedRecipient.address, amount],
              },
              bundlerClient!,
              smartWalletAccount,
            )
          : await walletClient.writeContract({
              abi: erc20Abi,
              address: tokenAddress,
              functionName: "transfer",
              args: [resolvedRecipient.address, amount],
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
          error: serializeError(err),
        });
        await shutdownAnalytics();
        return outputErrorAndExit(
          json,
          `Transaction failed: ${err instanceof Error ? err.message : String(err)}`,
          gasErrorSuggestion(err, smartWalletAccount ?? privateKeyAccount),
        );
      }

      // Smart wallet sends settle inside the user operation; only EOA
      // transactions need an explicit receipt wait.
      if (!smartWalletAccount) {
        await publicClient.waitForTransactionReceipt({ hash: txHash });
      }

      // ── Record spend in budget ledger ───────────────────────────────
      if (budget && !budget.optedOut && amountUsd != null) {
        const now = new Date();
        const updated = appendSpend(
          budget,
          {
            at: now.toISOString(),
            usd: amountUsd,
            skill: `send ${symbol} to ${resolvedRecipient.address.slice(0, 10)}...`,
          },
          now,
        );
        saveBudget(updated);
      }
      // ────────────────────────────────────────────────────────────────

      printSendResult(json, {
        name: tokenName,
        symbol,
        address: tokenAddress,
        amount,
        decimals,
        amountFormatted,
        amountUsd,
        recipient: resolvedRecipient,
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
