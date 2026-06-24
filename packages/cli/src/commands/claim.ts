import confirm from "@inquirer/confirm";
import {
  getProfile,
  prepareUserOperation,
  setApiKey,
  submitUserOperation,
  toGenericCall,
  toUserOperationCalls,
} from "@zoralabs/coins-sdk";
import { Command } from "commander";
import { formatUnits, isAddress, type Address } from "viem";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import { getApiKey } from "../lib/config.js";
import { safeExit, SUCCESS } from "../lib/exit.js";
import { formatAmountDisplay } from "../lib/format.js";
import { gasErrorSuggestion } from "../lib/gas.js";
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";

// Creator coins are 18-decimal ERC-20s. Half the supply vests linearly to the
// creator and is released by calling claimVesting() on the coin itself (tokens
// go to the payout recipient). getClaimableAmount() is the pending, not-yet-
// claimed balance, so we can show it and skip the tx when there's nothing to do.
const CREATOR_COIN_DECIMALS = 18;
const CREATOR_COIN_VESTING_ABI = [
  {
    type: "function",
    name: "claimVesting",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "getClaimableAmount",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

export const claimCommand = new Command("claim")
  .description("Claim vested rewards from your creator coin")
  .option(
    "--coin <address>",
    "Creator coin address to claim from (defaults to your own)",
  )
  .option("--yes", "Skip confirmation and execute directly")
  .action(async function (
    this: Command,
    opts: { coin?: string; yes?: boolean },
  ) {
    const json = getJson(this);

    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

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

    // Resolve the creator coin: an explicit --coin, otherwise the creator coin
    // tied to the active wallet's Zora profile.
    let coinAddress: Address;
    if (opts.coin) {
      if (!isAddress(opts.coin)) {
        return outputErrorAndExit(json, `Invalid --coin address: ${opts.coin}`);
      }
      coinAddress = opts.coin;
    } else {
      let resolved: string | undefined;
      try {
        const response = await getProfile({ identifier: walletAddress });
        resolved = response?.data?.profile?.creatorCoin?.address;
      } catch (err) {
        return outputErrorAndExit(
          json,
          `Failed to look up your creator coin: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
      if (!resolved || !isAddress(resolved)) {
        return outputErrorAndExit(
          json,
          "No creator coin found for your wallet.",
          "Create your creator coin on Zora first, or pass one with --coin <address>.",
        );
      }
      coinAddress = resolved;
    }

    let claimable: bigint;
    try {
      claimable = await publicClient.readContract({
        abi: CREATOR_COIN_VESTING_ABI,
        address: coinAddress,
        functionName: "getClaimableAmount",
      });
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Failed to read claimable rewards: ${err instanceof Error ? err.message : String(err)}`,
        "Make sure --coin points to a Zora creator coin.",
      );
    }

    if (claimable === 0n) {
      track("cli_claim", {
        action: "nothing_to_claim",
        coin_address: coinAddress,
        output_format: json ? "json" : "static",
        success: true,
      });
      if (json) {
        return outputJson({
          action: "claim",
          coin: coinAddress,
          claimable: "0",
          claimed: false,
        });
      }
      console.log(`\n Nothing to claim yet for ${coinAddress}.`);
      console.log("   Vested rewards accrue over time — check back later.\n");
      return;
    }

    const claimableFormatted = formatAmountDisplay(
      claimable,
      CREATOR_COIN_DECIMALS,
    );

    if (!opts.yes) {
      console.log("\n Claim creator coin rewards\n");
      console.log(`   Coin         ${coinAddress}`);
      console.log(`   Claimable    ${claimableFormatted}\n`);
      const ok = await confirm({ message: "Confirm?", default: false });
      if (!ok) {
        console.error("Aborted.");
        return safeExit(SUCCESS);
      }
    }

    let txHash: `0x${string}`;
    try {
      if (smartWalletAccount) {
        // submitUserOperation resolves with an already-settled receipt, so the
        // smart-wallet path needs no separate receipt wait (unlike the EOA one).
        const userOperation = await prepareUserOperation({
          bundlerClient: bundlerClient!,
          account: smartWalletAccount,
          calls: toUserOperationCalls([
            toGenericCall({
              abi: CREATOR_COIN_VESTING_ABI,
              address: coinAddress,
              functionName: "claimVesting",
            }),
          ]),
        });
        const receipt = await submitUserOperation({
          bundlerClient: bundlerClient!,
          account: smartWalletAccount,
          userOperation,
        });
        if (!receipt.success) {
          throw new Error(
            `User operation reverted${receipt.reason ? `: ${receipt.reason}` : ""}`,
          );
        }
        txHash = receipt.receipt.transactionHash;
      } else {
        // EOA transactions settle out-of-band, so wait for the receipt.
        txHash = await walletClient.writeContract({
          abi: CREATOR_COIN_VESTING_ABI,
          address: coinAddress,
          functionName: "claimVesting",
        });
        await publicClient.waitForTransactionReceipt({ hash: txHash });
      }
    } catch (err) {
      track("cli_claim", {
        coin_address: coinAddress,
        output_format: json ? "json" : "static",
        success: false,
        error_type: err instanceof Error ? err.constructor.name : "unknown",
      });
      await shutdownAnalytics();
      return outputErrorAndExit(
        json,
        `Claim failed: ${err instanceof Error ? err.message : String(err)}`,
        gasErrorSuggestion(err, smartWalletAccount ?? privateKeyAccount),
      );
    }

    if (json) {
      outputJson({
        action: "claim",
        coin: coinAddress,
        claimed: {
          amount: formatUnits(claimable, CREATOR_COIN_DECIMALS),
          raw: claimable.toString(),
        },
        tx: txHash,
      });
    } else {
      console.log("\n Claimed creator coin rewards\n");
      console.log(`   Coin         ${coinAddress}`);
      console.log(`   Claimed      ${claimableFormatted}`);
      console.log(`   Tx           ${txHash}\n`);
    }

    track("cli_claim", {
      coin_address: coinAddress,
      amount: claimableFormatted,
      transactionHash: txHash,
      output_format: json ? "json" : "static",
      success: true,
      tx_hash: txHash,
    });
  });
