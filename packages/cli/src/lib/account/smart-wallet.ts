import {
  Address,
  decodeAbiParameters,
  getAddress,
  Hex,
  isAddressEqual,
} from "viem";
import {
  toCoinbaseSmartAccount,
  ToCoinbaseSmartAccountReturnType,
} from "viem/account-abstraction";
import { base } from "viem/chains";
import { createPublicClient } from "../client/public.js";
import type { ChainClient } from "../agent/zora-client.js";
import { createPrivateKeyAccount } from "./wallet.js";

export const SMART_WALLET_ABI = [
  {
    inputs: [{ name: "index", type: "uint256" }],
    name: "ownerAtIndex",
    outputs: [{ name: "", type: "bytes" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "nextOwnerIndex",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

export type SmartWalletOwner = {
  index: number;
  address: Address | null;
  raw: Hex;
};

/** A real wallet has a handful of owners; a larger count means a bad read. */
const MAX_SMART_WALLET_OWNERS = 256n;

/**
 * Returns the owners of a smart wallet, reading the owner set from its actual
 * on-chain layout. Typed against the structural {@link ChainClient} so both the
 * viem public client (buy/sell/post) and the XMTP auth provider can share it.
 */
export const getSmartWalletOwners = async (
  client: ChainClient,
  smartWalletAddress: Address,
): Promise<SmartWalletOwner[]> => {
  // returns the next index that will be used to add a new owner (so, this is the total number of owners)
  const nextIndex = (await client.readContract({
    address: smartWalletAddress,
    abi: SMART_WALLET_ABI,
    functionName: "nextOwnerIndex",
  })) as bigint;

  // Guard against a garbage read driving an unbounded loop.
  if (nextIndex > MAX_SMART_WALLET_OWNERS) {
    throw new Error(
      `Smart wallet ${smartWalletAddress} reports an implausible owner count (${nextIndex})`,
    );
  }

  const owners: SmartWalletOwner[] = [];

  for (let i = 0n; i < nextIndex; i++) {
    const raw = (await client.readContract({
      address: smartWalletAddress,
      abi: SMART_WALLET_ABI,
      functionName: "ownerAtIndex",
      args: [i],
    })) as Hex;

    let address: Address | null = null;

    if (raw.length === 2 + 64) {
      const [decoded] = decodeAbiParameters([{ type: "address" }], raw);
      address = getAddress(decoded);
    }

    owners.push({ index: Number(i), address, raw });
  }

  return owners;
};

/**
 * Finds the index of an owner in a smart wallet
 */
const findOwnerIndex = (
  owners: SmartWalletOwner[],
  expected: Address,
): number => {
  const match = owners.find(
    (owner) =>
      owner.address !== null && isAddressEqual(owner.address, expected),
  );
  if (!match) {
    const summary = owners
      .map(
        (owner) =>
          `  [${owner.index}] ${owner.address ?? `non-EOA (${owner.raw})`}`,
      )
      .join("\n");
    throw new Error(
      `Signer ${expected} is not an owner of the smart wallet. On-chain owners:\n${summary}`,
    );
  }
  return match.index;
};

/**
 * Creates a viem smart wallet account from a smart wallet address and private key
 */
export const createSmartWalletAccount = async ({
  smartWalletAddress,
  privateKey,
}: {
  /**
   * The address of the smart wallet
   */
  smartWalletAddress: Address;
  /**
   * The private key of the owner of the smart wallet
   */
  privateKey: string;
}): Promise<SmartWalletAccount> => {
  const client = createPublicClient();

  const signer = createPrivateKeyAccount(privateKey);

  const owners = await getSmartWalletOwners(client, smartWalletAddress);
  const ownerIndex = findOwnerIndex(owners, signer.address);

  const account = await toCoinbaseSmartAccount({
    client,
    owners: [signer],
    ownerIndex,
    address: smartWalletAddress,
  });

  return account as SmartWalletAccount;
};

export type SmartWalletAccount = ToCoinbaseSmartAccountReturnType & {
  client: ToCoinbaseSmartAccountReturnType["client"] & { chain: typeof base };
};
