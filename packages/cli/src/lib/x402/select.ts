import { type Address, getAddress } from "viem";
import type { PublicClient } from "viem";
import { erc20Abi } from "viem";
import type { PaymentRequirements } from "@x402/core/types";
import { BASE_CHAIN_ID } from "../constants.js";

/** x402 v2's CAIP-2 network identifier for Base mainnet. */
export const BASE_NETWORK = "eip155:8453";

/**
 * Only the contract-read capability is needed here. Typing to this avoids
 * chain-formatter generic mismatches between the CLI's Base-bound public client
 * and viem's default `PublicClient`.
 */
export type ReadOnlyClient = Pick<PublicClient, "readContract">;

/**
 * Identifiers a 402 response might use for Base mainnet. x402 v2 uses CAIP-2
 * (`eip155:8453`), but we also accept the v1 name `base` and the raw chain id
 * and normalize them so x402's scheme code (keyed on the registered network)
 * matches.
 */
const BASE_NETWORK_ALIASES = new Set([
  BASE_NETWORK,
  "base",
  String(BASE_CHAIN_ID),
]);

export const isBaseNetwork = (network: string): boolean =>
  BASE_NETWORK_ALIASES.has(network.toLowerCase());

export type SelectionResult =
  | { kind: "selected"; requirement: PaymentRequirements; balance: bigint }
  | { kind: "none"; reason: string };

const sameAddress = (a: string, b: string): boolean => {
  try {
    return getAddress(a) === getAddress(b);
  } catch {
    return false;
  }
};

/**
 * Pick a payable entry from an x402 `accepts` array.
 *
 * An entry is payable when it is the `exact` scheme on Base mainnet, its `asset`
 * is an ERC-20 the wallet holds, and the held balance covers `amount`. When
 * several qualify, an explicit `--asset` preference wins; otherwise the first
 * qualifying entry (in server-provided order) is chosen.
 *
 * Returns the requirement with its `network` normalized to `eip155:8453`.
 */
export const selectPayableRequirement = async ({
  accepts,
  publicClient,
  walletAddress,
  preferredAsset,
}: {
  accepts: PaymentRequirements[];
  publicClient: ReadOnlyClient;
  walletAddress: Address;
  preferredAsset?: Address;
}): Promise<SelectionResult> => {
  const baseExact = accepts.filter(
    (r) => r.scheme === "exact" && isBaseNetwork(r.network),
  );

  if (baseExact.length === 0) {
    return {
      kind: "none",
      reason:
        "No payable entry: none use the 'exact' scheme on Base mainnet. Only Base (exact) payments are supported.",
    };
  }

  // Order so an explicit asset preference is tried first.
  const ordered = preferredAsset
    ? [
        ...baseExact.filter((r) => sameAddress(r.asset, preferredAsset)),
        ...baseExact.filter((r) => !sameAddress(r.asset, preferredAsset)),
      ]
    : baseExact;

  // Read each distinct asset's balance once.
  const balances = new Map<string, bigint>();
  for (const requirement of ordered) {
    const assetKey = requirement.asset.toLowerCase();
    if (!balances.has(assetKey)) {
      try {
        const balance = await publicClient.readContract({
          abi: erc20Abi,
          address: requirement.asset as Address,
          functionName: "balanceOf",
          args: [walletAddress],
        });
        balances.set(assetKey, balance);
      } catch {
        balances.set(assetKey, 0n);
      }
    }

    const balance = balances.get(assetKey)!;
    const required = BigInt(requirement.amount);
    // Require a positive amount: a zero-amount requirement is degenerate (there's
    // nothing to authorize) and `balance >= 0n` would otherwise always pass.
    if (required > 0n && balance >= required) {
      return {
        kind: "selected",
        requirement: { ...requirement, network: BASE_NETWORK },
        balance,
      };
    }
  }

  return {
    kind: "none",
    reason:
      preferredAsset !== undefined
        ? `No payable entry: wallet ${walletAddress} doesn't hold enough of the requested asset on Base.`
        : `No payable entry: wallet ${walletAddress} doesn't hold enough of any required Base asset to cover payment.`,
  };
};

/**
 * Synchronous selector for the `--url` (pay-and-fetch) path, where @x402/fetch
 * drives payment creation and a balance read isn't available. Picks the first
 * Base `exact` entry (honoring an asset preference) and enforces the `maxValue`
 * cap, throwing if nothing matches or the amount exceeds the cap. Returns the
 * requirement with its `network` normalized to `eip155:8453`.
 */
export const selectForFetch = (
  accepts: PaymentRequirements[],
  { preferredAsset, maxValue }: { preferredAsset?: Address; maxValue?: bigint },
): PaymentRequirements => {
  const baseExact = accepts.filter(
    (r) => r.scheme === "exact" && isBaseNetwork(r.network),
  );
  const chosen = preferredAsset
    ? (baseExact.find((r) => sameAddress(r.asset, preferredAsset)) ??
      baseExact[0])
    : baseExact[0];
  if (!chosen) {
    throw new Error("No 'exact' payment requirement on Base in response.");
  }
  if (maxValue !== undefined && BigInt(chosen.amount) > maxValue) {
    throw new Error(
      `Payment of ${chosen.amount} exceeds --max-value cap of ${maxValue}.`,
    );
  }
  return { ...chosen, network: BASE_NETWORK };
};
