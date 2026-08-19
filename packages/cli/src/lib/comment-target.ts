import { getCoin, setApiKey } from "@zoralabs/coins-sdk";
import { isAddress, type Address } from "viem";
import {
  CoinArgError,
  coinArgsToRef,
  formatAmbiguousError,
  parsePositionalCoinArgs,
  resolveAmbiguousName,
  resolveCoin,
} from "./coin-ref.js";
import { getApiKey } from "./config.js";
import { outputErrorAndExit } from "./output.js";

/** Resolved coin reference: enough to read or write comments. */
export type CoinTarget = { address: Address; name: string };

const resolveApiKey = () => {
  const apiKey = getApiKey();
  if (apiKey) {
    setApiKey(apiKey);
  }
};

/**
 * Resolves the positional coin args (address, `creator-coin <name>`, `trend
 * <name>`, or a bare name) to a single coin address + display name. Exits with a
 * helpful error when the reference is invalid, missing, or ambiguous. Shared by
 * the `comment` post and `comment list` subcommands.
 */
export async function resolveCoinTarget(
  json: boolean,
  typeOrId: string | undefined,
  identifier: string | undefined,
  command: string,
): Promise<CoinTarget> {
  // Guard before parsing: parsePositionalCoinArgs assumes a defined first arg
  // (it calls typeOrId.startsWith), so a bare `comment list` would otherwise
  // throw a raw TypeError instead of a usage message.
  if (!typeOrId) {
    return outputErrorAndExit(
      json,
      "Missing coin.",
      `Usage: zora ${command} <coin>`,
    );
  }

  let parsed;
  try {
    parsed = parsePositionalCoinArgs(typeOrId, identifier);
  } catch (err) {
    if (err instanceof CoinArgError) {
      return outputErrorAndExit(json, err.message, err.suggestion);
    }
    throw err;
  }

  resolveApiKey();

  if (parsed.kind === "address") {
    if (!isAddress(parsed.address)) {
      return outputErrorAndExit(json, `Invalid address: ${parsed.address}`);
    }
    // Look up the name for nicer output, but don't fail the command if the
    // metadata lookup misses — the address is enough to read/write comments.
    let name: string = parsed.address;
    try {
      const response = await getCoin({ address: parsed.address });
      name = response.data?.zora20Token?.name ?? parsed.address;
    } catch {
      // ignore — fall back to the address as the display name
    }
    return { address: parsed.address as Address, name };
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
        command,
      );
      return outputErrorAndExit(json, message, suggestion);
    }
    return {
      address: ambResult.coin.address as Address,
      name: ambResult.coin.name,
    };
  }

  // typed (creator-coin / trend)
  try {
    const result = await resolveCoin(coinArgsToRef(parsed));
    if (result.kind === "not-found") {
      return outputErrorAndExit(json, result.message, result.suggestion);
    }
    return {
      address: result.coin.address as Address,
      name: result.coin.name,
    };
  } catch (err) {
    return outputErrorAndExit(
      json,
      `Request failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}
