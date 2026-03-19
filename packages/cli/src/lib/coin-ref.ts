import { getCoin, getProfile } from "@zoralabs/coins-sdk";
import type { CoinType } from "./types.js";

export type CoinRef =
  | { kind: "address"; address: string }
  | { kind: "prefixed"; type: CoinType; name: string }
  | { kind: "ambiguous"; name: string };

export interface ResolvedCoin {
  name: string;
  address: string;
  coinType: CoinType | "unknown";
  marketCap: string;
  marketCapDelta24h: string;
  volume24h: string;
  uniqueHolders: number;
  createdAt: string | undefined;
  creatorAddress: string | undefined;
  creatorHandle: string | undefined;
}

export type ResolveCoinResult =
  | { kind: "found"; coin: ResolvedCoin }
  | { kind: "not-found"; message: string; suggestion?: string };

const COIN_TYPE_MAP: Record<string, CoinType> = {
  CONTENT: "post",
  CREATOR: "creator-coin",
  TREND: "trend",
};

function mapCoinType(raw: string | undefined): CoinType | "unknown" {
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
    uniqueHolders: token.uniqueHolders ?? 0,
    createdAt: token.createdAt,
    creatorAddress: token.creatorAddress,
    creatorHandle: token.creatorProfile?.handle,
  };
}

export function parseCoinRef(identifier: string, type?: string): CoinRef {
  if (identifier.startsWith("0x")) {
    return { kind: "address", address: identifier };
  }

  if (type === "creator-coin") {
    return { kind: "prefixed", type: "creator-coin", name: identifier };
  }

  return { kind: "ambiguous", name: identifier };
}

async function resolveByAddress(address: string): Promise<ResolveCoinResult> {
  const response = await getCoin({ address });

  if (response.error || !response.data?.zora20Token) {
    return { kind: "not-found", message: `No coin found at address ${address}` };
  }

  return { kind: "found", coin: coinFromToken(response.data.zora20Token) };
}

async function resolveByCreatorName(name: string): Promise<ResolveCoinResult> {
  const response = await getProfile({ identifier: name });

  if (response.error || !response.data?.profile) {
    return { kind: "not-found", message: `No creator found with name "${name}"` };
  }

  const profile = response.data.profile;
  if (!profile.creatorCoin) {
    return { kind: "not-found", message: `"${name}" does not have a creator coin` };
  }

  return resolveByAddress(profile.creatorCoin.address);
}

export async function resolveCoin(ref: CoinRef): Promise<ResolveCoinResult> {
  switch (ref.kind) {
    case "address":
      return resolveByAddress(ref.address);
    case "prefixed":
      return resolveByCreatorName(ref.name);
    case "ambiguous":
      return resolveByCreatorName(ref.name);
  }
}
