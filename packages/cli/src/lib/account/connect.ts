import {
  type Address,
  type Hex,
  decodeAbiParameters,
  getAddress,
  isAddressEqual,
} from "viem";
import { isDeployed, predictAddress } from "../agent/smart-wallet.js";
import type { ChainClient } from "../agent/zora-client.js";
import { createPrivateKeyAccount } from "./wallet.js";
import { SMART_WALLET_ABI } from "./smart-wallet.js";

/** The smart wallet (Zora account) a private key was found to control. */
export interface ConnectionResult {
  /** EOA derived from the connecting private key — owner of the smart wallet. */
  ownerAddress: Address;
  /** Smart wallet (Zora account) address that holds the coins, posts, profile. */
  smartWalletAddress: Address;
  /** true when found via deterministic prediction; false when supplied explicitly. */
  discovered: boolean;
}

/** No deployed smart wallet exists for the key's owner address. */
export class NoSmartWalletFoundError extends Error {
  readonly ownerAddress: Address;
  constructor(ownerAddress: Address) {
    super(`No deployed Zora smart wallet found for owner ${ownerAddress}.`);
    this.name = "NoSmartWalletFoundError";
    this.ownerAddress = ownerAddress;
  }
}

/** An explicitly-supplied smart wallet address has no code on Base. */
export class SmartWalletNotDeployedError extends Error {
  readonly smartWalletAddress: Address;
  constructor(smartWalletAddress: Address) {
    super(`Smart wallet ${smartWalletAddress} is not deployed on Base.`);
    this.name = "SmartWalletNotDeployedError";
    this.smartWalletAddress = smartWalletAddress;
  }
}

/** The connecting key is not an owner of the supplied smart wallet. */
export class NotSmartWalletOwnerError extends Error {
  readonly ownerAddress: Address;
  readonly smartWalletAddress: Address;
  constructor(ownerAddress: Address, smartWalletAddress: Address) {
    super(
      `${ownerAddress} is not an owner of smart wallet ${smartWalletAddress}.`,
    );
    this.name = "NotSmartWalletOwnerError";
    this.ownerAddress = ownerAddress;
    this.smartWalletAddress = smartWalletAddress;
  }
}

/** Reads the on-chain owner addresses of a deployed Coinbase smart wallet. */
async function readOwners(
  client: ChainClient,
  smartWalletAddress: Address,
): Promise<Address[]> {
  const nextIndex = (await client.readContract({
    address: smartWalletAddress,
    abi: SMART_WALLET_ABI,
    functionName: "nextOwnerIndex",
  })) as bigint;

  const owners: Address[] = [];
  for (let i = 0n; i < nextIndex; i++) {
    const raw = (await client.readContract({
      address: smartWalletAddress,
      abi: SMART_WALLET_ABI,
      functionName: "ownerAtIndex",
      args: [i],
    })) as Hex;
    // Owners are stored as ABI-encoded bytes; a 32-byte value decodes to an EOA
    // (a longer value is a passkey/contract owner, which can't sign here — skip).
    if (raw.length === 2 + 64) {
      const [decoded] = decodeAbiParameters([{ type: "address" }], raw);
      owners.push(getAddress(decoded));
    }
  }
  return owners;
}

/**
 * Resolves the Zora smart wallet (account) controlled by a private key.
 *
 * A standard Zora account is a Coinbase Smart Wallet whose sole creation owner is
 * the account's key — the embedded (Privy) wallet a user exports. That makes its
 * address deterministic: `ZoraAccountManager.getAddress([owner], nonce)`. So from
 * just the key we predict the address and confirm it's deployed on-chain, with no
 * API call or stored state.
 *
 * When `smartWalletOverride` is given we skip prediction (e.g. the account has a
 * non-standard owner set, or isn't reachable via prediction) but still verify it:
 * the address must be deployed AND list the key as an owner, so we never save a
 * wallet the key can't actually sign for.
 */
export async function resolveConnection(params: {
  privateKey: string;
  client: ChainClient;
  smartWalletOverride?: Address;
}): Promise<ConnectionResult> {
  const ownerAddress = createPrivateKeyAccount(params.privateKey).address;

  if (params.smartWalletOverride) {
    const smartWalletAddress = params.smartWalletOverride;
    if (!(await isDeployed(params.client, smartWalletAddress))) {
      throw new SmartWalletNotDeployedError(smartWalletAddress);
    }
    const owners = await readOwners(params.client, smartWalletAddress);
    if (!owners.some((o) => isAddressEqual(o, ownerAddress))) {
      throw new NotSmartWalletOwnerError(ownerAddress, smartWalletAddress);
    }
    return { ownerAddress, smartWalletAddress, discovered: false };
  }

  // The deterministic single-owner account: when deployed, the key is owner #0 by
  // construction, so no further ownership check is needed.
  const predicted = await predictAddress(params.client, [ownerAddress]);
  if (!(await isDeployed(params.client, predicted))) {
    throw new NoSmartWalletFoundError(ownerAddress);
  }
  return { ownerAddress, smartWalletAddress: predicted, discovered: true };
}
