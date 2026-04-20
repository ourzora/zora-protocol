import { getCoin, getProfile, getTrend } from "@zoralabs/coins-sdk";
import type { CoinType } from "./types.js";
import { formatCompactUsd } from "./format.js";

export type CoinRef =
  | { kind: "address"; address: string }
  | { kind: "prefixed"; type: CoinType; name: string }
  | { kind: "ambiguous"; name: string };

// --- Positional arg parsing ---

const TYPE_KEYWORDS = new Set<string>(["creator-coin", "trend"]);

export type ParsedCoinArgs =
  | { kind: "typed"; type: CoinType; identifier: string }
  | { kind: "address"; address: string }
  | { kind: "ambiguous-name"; name: string };

export class CoinArgError extends Error {
  suggestion?: string;
  constructor(message: string, suggestion?: string) {
    super(message);
    this.suggestion = suggestion;
  }
}

export function parsePositionalCoinArgs(
  firstArg: string,
  secondArg: string | undefined,
): ParsedCoinArgs {
  if (TYPE_KEYWORDS.has(firstArg)) {
    if (!secondArg) {
      throw new CoinArgError(
        `Missing identifier after "${firstArg}".`,
        `Usage: zora <command> ${firstArg} <name>`,
      );
    }
    return { kind: "typed", type: firstArg as CoinType, identifier: secondArg };
  }

  if (firstArg.startsWith("0x")) {
    return { kind: "address", address: firstArg };
  }

  return { kind: "ambiguous-name", name: firstArg };
}

export function coinArgsToRef(parsed: ParsedCoinArgs): CoinRef {
  switch (parsed.kind) {
    case "typed":
      return { kind: "prefixed", type: parsed.type, name: parsed.identifier };
    case "address":
      return { kind: "address", address: parsed.address };
    case "ambiguous-name":
      return { kind: "ambiguous", name: parsed.name };
  }
}

// --- Ambiguous name resolution ---

export type AmbiguousResult =
  | { kind: "found"; coin: ResolvedCoin }
  | { kind: "ambiguous"; creator: ResolvedCoin; trend: ResolvedCoin }
  | { kind: "not-found"; message: string };

export async function resolveAmbiguousByNameAndBalance(
  name: string,
  getBalance: (address: string) => Promise<bigint>,
): Promise<AmbiguousResult> {
  const result = await resolveAmbiguousName(name);
  if (result.kind !== "ambiguous") return result;

  const [creatorBal, trendBal] = await Promise.all([
    getBalance(result.creator.address),
    getBalance(result.trend.address),
  ]);
  if (creatorBal > 0n && trendBal === 0n)
    return { kind: "found", coin: result.creator };
  if (trendBal > 0n && creatorBal === 0n)
    return { kind: "found", coin: result.trend };
  return result;
}

export async function resolveAmbiguousName(
  name: string,
): Promise<AmbiguousResult> {
  const [creatorResult, trendResult] = await Promise.all([
    resolveByCreatorName(name),
    resolveByTrendTicker(name),
  ]);

  const creatorFound =
    creatorResult.kind === "found" ? creatorResult.coin : null;
  const trendFound = trendResult.kind === "found" ? trendResult.coin : null;

  if (creatorFound && trendFound) {
    return { kind: "ambiguous", creator: creatorFound, trend: trendFound };
  }

  if (creatorFound) {
    return { kind: "found", coin: creatorFound };
  }

  if (trendFound) {
    return { kind: "found", coin: trendFound };
  }

  return {
    kind: "not-found",
    message: `No coin found matching "${name}".`,
  };
}

export function formatAmbiguousError(
  name: string,
  creator: ResolvedCoin,
  trend: ResolvedCoin,
  command: string,
): { message: string; suggestion: string } {
  const creatorMcap = formatCompactUsd(creator.marketCap);
  const trendMcap = formatCompactUsd(trend.marketCap);
  return {
    message: [
      `Multiple coins match "${name}":`,
      `  creator-coin  ${creator.name}  ${creatorMcap} mcap`,
      `  trend         ${trend.name}  ${trendMcap} mcap`,
    ].join("\n"),
    suggestion: `Use: zora ${command} creator-coin ${name}  or  zora ${command} trend ${name}`,
  };
}

export interface ResolvedCoin {
  name: string;
  address: string;
  coinType: CoinType | "unknown";
  marketCap: string;
  marketCapDelta24h: string;
  volume24h: string;
  totalSupply: string;
  uniqueHolders: number;
  createdAt: string | undefined;
  creatorAddress: string | undefined;
  creatorHandle: string | undefined;
  platformBlocked: boolean;
}

export type ResolveCoinResult =
  | { kind: "found"; coin: ResolvedCoin }
  | { kind: "not-found"; message: string; suggestion?: string };

const COIN_TYPE_MAP: Record<string, CoinType> = {
  CONTENT: "post",
  CREATOR: "creator-coin",
  TREND: "trend",
};

export function mapCoinType(raw: string | undefined): CoinType | "unknown" {
  if (!raw) return "unknown";
  return COIN_TYPE_MAP[raw] ?? "unknown";
}

function coinFromToken(token: any): ResolvedCoin {
  return {
    name: token.name ?? "Unknown",
    address: token.address ?? "",
    coinType: mapCoinType(token.coinType),
    marketCap: token.marketCap ?? "0",
    marketCapDelta24h: token.marketCapDelta24h ?? "0",
    volume24h: token.volume24h ?? "0",
    totalSupply: token.totalSupply ?? "0",
    uniqueHolders: token.uniqueHolders ?? 0,
    createdAt: token.createdAt,
    creatorAddress: token.creatorAddress,
    creatorHandle: token.creatorProfile?.handle,
    platformBlocked: token.platformBlocked ?? false,
  };
}

export function parseCoinRef(identifier: string, type?: string): CoinRef {
  if (identifier.startsWith("0x")) {
    return { kind: "address", address: identifier };
  }

  if (type === "creator-coin") {
    return { kind: "prefixed", type: "creator-coin", name: identifier };
  }

  if (type === "trend") {
    return { kind: "prefixed", type: "trend", name: identifier };
  }

  return { kind: "ambiguous", name: identifier };
}

async function resolveByAddress(address: string): Promise<ResolveCoinResult> {
  const response = await getCoin({ address });

  if (response.error || !response.data?.zora20Token) {
    return {
      kind: "not-found",
      message: `No coin found at address ${address}`,
    };
  }

  return { kind: "found", coin: coinFromToken(response.data.zora20Token) };
}

async function resolveByTrendTicker(
  ticker: string,
): Promise<ResolveCoinResult> {
  const response = await getTrend({ ticker });

  if (response.error || !response.data?.trendCoin) {
    return {
      kind: "not-found",
      message: `No trend coin found with ticker "${ticker}"`,
    };
  }

  return { kind: "found", coin: coinFromToken(response.data.trendCoin) };
}

async function resolveByCreatorName(name: string): Promise<ResolveCoinResult> {
  const response = await getProfile({ identifier: name });

  if (response.error || !response.data?.profile) {
    return {
      kind: "not-found",
      message: `No creator found with name "${name}"`,
    };
  }

  const profile = response.data.profile;
  if (!profile.creatorCoin) {
    return {
      kind: "not-found",
      message: `"${name}" does not have a creator coin`,
    };
  }

  return resolveByAddress(profile.creatorCoin.address);
}

export async function resolveCoin(ref: CoinRef): Promise<ResolveCoinResult> {
  switch (ref.kind) {
    case "address":
      return resolveByAddress(ref.address);
    case "prefixed":
      if (ref.type === "trend") {
        return resolveByTrendTicker(ref.name);
      }
      return resolveByCreatorName(ref.name);
    case "ambiguous":
      return resolveByCreatorName(ref.name);
  }
}
