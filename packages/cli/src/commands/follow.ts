import { getProfile, setApiKey } from "@zoralabs/coins-sdk";
import { Command } from "commander";
import { erc20Abi, isAddress, type Address } from "viem";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import { getApiKey, getPrivateKey } from "../lib/config.js";
import { formatError, serializeError } from "../lib/errors.js";
import {
  followProfile,
  unfollowProfile,
  type FollowingStatus,
  type FollowResult,
} from "../lib/follow.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { ensurePrivySession } from "../lib/privy-session.js";
import { createClients, normalizeKey, resolveAccounts } from "../lib/wallet.js";

type FollowAction = "follow" | "unfollow";

/**
 * A non-empty, non-placeholder handle. When the target has no Zora profile the
 * API returns a truncated wallet address as the handle (e.g. "0x1234…5678"),
 * which we don't want to present as an @-handle or build a profile URL from.
 */
function isPlaceholderName(name: string): boolean {
  return name.startsWith("0x") || name.includes("…") || name.includes("...");
}

/** A human label for the target: `@handle` when it has a real handle, else its id. */
function displayName(result: FollowResult): string {
  return isPlaceholderName(result.handle)
    ? result.profileId
    : `@${result.handle}`;
}

/** A short note describing the mutual-follow relationship, when relevant. */
function relationshipNote(status: FollowingStatus): string | undefined {
  if (status === "MUTUAL_FOLLOWING") return "You follow each other.";
  if (status === "FOLLOWED") return "They still follow you.";
  return undefined;
}

/**
 * Enforces the follow gate: you can only follow a profile whose creator coin you
 * hold. Looks up the target's creator coin (public profile API, no auth) and
 * reads your on-chain balance of it — checking the smart wallet when one is
 * configured, else the EOA, since that's where coins bought with `zora buy`
 * land. Exits with actionable guidance when the target has no creator coin or
 * you hold none of it; returns normally when the gate is satisfied.
 */
async function requireCreatorCoinHolding(
  json: boolean,
  identifier: string,
): Promise<void> {
  // An API key (when set) raises the rate limit on the profile lookup.
  const apiKey = getApiKey();
  if (apiKey) setApiKey(apiKey);

  let profile;
  try {
    const response = await getProfile({ identifier });
    profile = response?.data?.profile;
  } catch (err) {
    return outputErrorAndExit(
      json,
      `Couldn't look up "${identifier}": ${formatError(err)}`,
    );
  }
  if (!profile) {
    return outputErrorAndExit(
      json,
      `No Zora profile found for "${identifier}".`,
      "Provide an existing Zora username or wallet address.",
    );
  }

  const label =
    profile.handle && !isPlaceholderName(profile.handle)
      ? `@${profile.handle}`
      : identifier;
  const coinAddress = profile.creatorCoin?.address;
  if (!coinAddress || !isAddress(coinAddress)) {
    return outputErrorAndExit(
      json,
      `${label} doesn't have a creator coin yet, so there's nothing to buy.`,
      "Following requires holding the profile's creator coin.",
    );
  }

  const { privateKeyAccount, smartWalletAccount } = await resolveAccounts();
  const wallet = smartWalletAccount?.address ?? privateKeyAccount.address;
  const { publicClient } = createClients(privateKeyAccount, smartWalletAccount);

  let balance: bigint;
  try {
    balance = await publicClient.readContract({
      abi: erc20Abi,
      address: coinAddress as Address,
      functionName: "balanceOf",
      args: [wallet],
    });
  } catch (err) {
    return outputErrorAndExit(
      json,
      `Couldn't check your creator-coin balance: ${formatError(err)}`,
    );
  }

  if (balance === 0n) {
    return outputErrorAndExit(
      json,
      `You must hold ${label}'s creator coin to follow them.`,
      `Buy some first: zora buy ${coinAddress} --eth 0.001`,
    );
  }
}

/**
 * Resolves the Privy access token for the configured wallet, reusing a cached
 * session where possible (a full SIWE sign-in is rate-limited — see
 * {@link ensurePrivySession}). Exits with guidance when sign-in fails.
 */
async function resolveToken(json: boolean, key: string): Promise<string> {
  try {
    const session = await ensurePrivySession({ privateKey: normalizeKey(key) });
    return session.accessToken;
  } catch (err) {
    return outputErrorAndExit(json, `Sign-in failed: ${formatError(err)}`);
  }
}

/**
 * Shared implementation for `zora follow` and `zora unfollow`. The two commands
 * differ in which mutation runs, the success wording, and the follow-only
 * creator-coin gate; everything else (parsing, auth, output) is identical.
 */
async function runFollow(
  command: Command,
  action: FollowAction,
  identifierArg: string | undefined,
): Promise<void> {
  const json = getJson(command);

  // Accept a leading `@` (how handles are usually written) and trim whitespace.
  const followeeId = (identifierArg ?? "").replace(/^@/, "").trim();
  if (!followeeId) {
    return outputErrorAndExit(
      json,
      `Missing user to ${action}.`,
      `Usage: zora ${action} <username | address>`,
    );
  }

  const key = process.env.ZORA_PRIVATE_KEY || getPrivateKey();
  if (!key) {
    return outputErrorAndExit(
      json,
      "No wallet configured.",
      "Run 'zora agent create' to set up your Zora agent.",
    );
  }

  // Following requires holding the target's creator coin. Unfollowing never
  // does — you can always walk a follow back. Gate before sign-in so we don't
  // burn a Privy session when the requirement isn't met.
  if (action === "follow") {
    await requireCreatorCoinHolding(json, followeeId);
  }

  const token = await resolveToken(json, key);

  let result: FollowResult;
  try {
    result =
      action === "follow"
        ? await followProfile(token, followeeId)
        : await unfollowProfile(token, followeeId);
  } catch (err) {
    track("cli_follow", {
      action,
      output_format: json ? "json" : "static",
      success: false,
      error_type: err instanceof Error ? err.constructor.name : "unknown",
      error: serializeError(err),
    });
    await shutdownAnalytics();
    const message = formatError(err);
    // The API rejects following yourself — turn the raw resolver error into
    // actionable guidance.
    if (action === "follow" && /yourself/i.test(message)) {
      return outputErrorAndExit(json, "You can't follow yourself.");
    }
    return outputErrorAndExit(
      json,
      `Failed to ${action} "${followeeId}": ${message}`,
      "Check the username or address is a real Zora profile and try again.",
    );
  }

  // The identifier resolved to the viewer's own profile, so nothing changed.
  // Record it like the other failure exits do (catch block above), so a
  // self-follow attempt isn't silently dropped from analytics.
  if (result.followingStatus === "SELF") {
    track("cli_follow", {
      action,
      output_format: json ? "json" : "static",
      success: false,
      error_type: "self",
    });
    await shutdownAnalytics();
    return outputErrorAndExit(json, `You can't ${action} yourself.`);
  }

  const label = displayName(result);
  const profileUrl = isPlaceholderName(result.handle)
    ? undefined
    : `https://zora.co/@${result.handle}`;
  const note = relationshipNote(result.followingStatus);

  track("cli_follow", {
    action,
    output_format: json ? "json" : "static",
    success: true,
    following_status: result.followingStatus,
  });

  outputData(json, {
    json: {
      action,
      followee: result.profileId,
      handle: result.handle,
      followingStatus: result.followingStatus,
      ...(profileUrl ? { profileUrl } : {}),
    },
    render: () => {
      console.log(
        `\n✓ ${action === "follow" ? "Following" : "Unfollowed"} ${label}`,
      );
      if (note) console.log(`  ${note}`);
      if (profileUrl) console.log(`  ${profileUrl}`);
      console.log("");
    },
  });
}

export const followCommand = new Command("follow")
  .description("Follow a Zora user whose creator coin you hold")
  .argument("[identifier]", "Username (@handle), wallet address, or account id")
  .action(async function (this: Command, identifier: string | undefined) {
    await runFollow(this, "follow", identifier);
  });

export const unfollowCommand = new Command("unfollow")
  .description("Unfollow a Zora user by username or address")
  .argument("[identifier]", "Username (@handle), wallet address, or account id")
  .action(async function (this: Command, identifier: string | undefined) {
    await runFollow(this, "unfollow", identifier);
  });
