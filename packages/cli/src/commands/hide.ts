import { setApiKey } from "@zoralabs/coins-sdk";
import { Command } from "commander";
import { isAddress } from "viem";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import { resolveAmbiguousName, resolveCoin } from "../lib/coin-ref.js";
import { getApiKey, getPrivateKey } from "../lib/config.js";
import { formatError, serializeError } from "../lib/errors.js";
import { BASE_CHAIN_ID } from "../lib/agent/zora-client.js";
import { hideCoin, unhideCoin, type HideResult } from "../lib/hide.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { ensurePrivySession } from "../lib/privy-session.js";
import { normalizeKey } from "../lib/wallet.js";

type HideAction = "hide" | "unhide";

/**
 * Parses the optional `--chain <id>` flag, defaulting to Base mainnet (the chain
 * every other CLI command operates on). Exits with guidance on a non-numeric value.
 */
function resolveChainId(json: boolean, raw: string | undefined): number {
  if (raw === undefined) return BASE_CHAIN_ID;
  const chainId = Number(raw);
  if (!Number.isInteger(chainId) || chainId <= 0) {
    return outputErrorAndExit(
      json,
      `Invalid --chain value: ${raw}`,
      "Pass a numeric chain id (default: 8453, Base mainnet).",
    );
  }
  return chainId;
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
 * Turns a coin identifier into a canonical coin address and a human label.
 *
 * - An address resolves directly; hiding is keyed purely by address, so when
 *   the indexer doesn't know it (e.g. spam not yet indexed) we still hide it,
 *   falling back to the raw address rather than erroring.
 * - A name is matched against both creator coins and trend coins (so a trend
 *   ticker resolves, matching the documented "creator/trend name" support);
 *   an ambiguous name that matches both is a hard error directing the user to
 *   the address.
 */
async function resolveCoinAddress(
  json: boolean,
  identifier: string,
): Promise<{ address: string; label: string }> {
  // An API key (when set) raises the rate limit on the coin lookup.
  const apiKey = getApiKey();
  if (apiKey) setApiKey(apiKey);

  if (isAddress(identifier)) {
    const result = await resolveCoin({ kind: "address", address: identifier });
    return result.kind === "found"
      ? { address: result.coin.address, label: result.coin.name }
      : { address: identifier, label: identifier };
  }

  const result = await resolveAmbiguousName(identifier);
  if (result.kind === "found") {
    return { address: result.coin.address, label: result.coin.name };
  }
  if (result.kind === "ambiguous") {
    return outputErrorAndExit(
      json,
      `Multiple coins match "${identifier}" (a creator coin and a trend coin).`,
      "Pass the coin address to choose which one to hide.",
    );
  }
  return outputErrorAndExit(
    json,
    result.message ?? `No coin found matching "${identifier}".`,
    "Pass a coin address, or a creator/trend name.",
  );
}

/**
 * Shared implementation for `zora coin hide` and `zora coin unhide`. The two
 * differ only in which mutation runs and the success wording; parsing, auth,
 * and output are identical. Hiding affects the viewer's own holdings and
 * profile across Zora — there is no holding requirement, so any coin can be
 * hidden (e.g. unwanted airdrops).
 */
async function runHide(
  command: Command,
  action: HideAction,
  identifierArg: string | undefined,
): Promise<void> {
  const json = getJson(command);

  const identifier = (identifierArg ?? "").trim();
  if (!identifier) {
    return outputErrorAndExit(
      json,
      `Missing coin to ${action}.`,
      `Usage: zora coin ${action} <address | name>`,
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

  const chainId = resolveChainId(json, command.opts().chain);
  const { address, label } = await resolveCoinAddress(json, identifier);
  const token = await resolveToken(json, key);

  let result: HideResult;
  try {
    result =
      action === "hide"
        ? await hideCoin(token, address, chainId)
        : await unhideCoin(token, address, chainId);
  } catch (err) {
    track("cli_hide", {
      action,
      coin: address,
      chain_id: chainId,
      output_format: json ? "json" : "static",
      success: false,
      error_type: err instanceof Error ? err.constructor.name : "unknown",
      error: serializeError(err),
    });
    await shutdownAnalytics();
    return outputErrorAndExit(
      json,
      `Failed to ${action} "${label}": ${formatError(err)}`,
      "Check the coin address or name and try again.",
    );
  }

  track("cli_hide", {
    action,
    coin: address,
    chain_id: chainId,
    output_format: json ? "json" : "static",
    success: true,
  });

  outputData(json, {
    json: {
      action,
      coin: address,
      hidden: action === "hide",
      profileId: result.profileId,
    },
    render: () => {
      const verb = action === "hide" ? "Hidden" : "Unhidden";
      console.log(`\n✓ ${verb} ${label}`);
      console.log(`  ${address}`);
      if (action === "hide") {
        console.log("  It won't show in your holdings or on your profile.");
      }
      console.log("");
    },
  });
}

export const coinHideCommand = new Command("hide")
  .description("Hide a coin from your holdings and profile")
  .argument("[identifier]", "Coin address, or a creator/trend name")
  .option(
    "--chain <id>",
    "Chain id the coin is on (default: 8453, Base mainnet)",
  )
  .action(async function (this: Command, identifier: string | undefined) {
    await runHide(this, "hide", identifier);
  });

export const coinUnhideCommand = new Command("unhide")
  .description("Unhide a previously hidden coin")
  .argument("[identifier]", "Coin address, or a creator/trend name")
  .option(
    "--chain <id>",
    "Chain id the coin is on (default: 8453, Base mainnet)",
  )
  .action(async function (this: Command, identifier: string | undefined) {
    await runHide(this, "unhide", identifier);
  });
