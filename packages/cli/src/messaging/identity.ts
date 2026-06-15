import { type Address, type Hex, hashMessage, toBytes } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { base } from "viem/chains";
import {
  type SmartWalletOwner,
  getOwnerIndexForWallet,
  toReplaySafeHash,
  wrapSignature,
} from "./signer.js";

/**
 * The contract the DM feature needs from the CLI's authenticated-action layer
 * (signing as the user's Zora identity). Implemented by
 * `createCliSmartWalletProvider` in `cli-auth-provider.ts`, which signs locally
 * as the smart wallet's external EOA owner and gets a Privy access token.
 *
 * CRITICAL: `signHash` must sign the **raw 32-byte hash** (the equivalent of the
 * browser's `secp256k1_sign`), returning a 65-byte signature with no EIP-191
 * prefix. A prefixed `personal_sign`/`signMessage` yields an invalid smart-wallet
 * (ERC-1271) signature and XMTP identity creation fails. This is the single
 * highest-risk integration point — verify it first.
 */
export interface PrivyAuthProvider {
  /** The shared XMTP inbox address — the user's Coinbase Smart Wallet. */
  getSmartWalletAddress(): Address;
  /** The Privy embedded wallet (an owner of the smart wallet) that signs. */
  getOwnerAddress(): Address;
  /** The smart wallet's owner set, used to derive the owner index. */
  getOwners(): readonly SmartWalletOwner[] | null;
  /** Sign a raw 32-byte hash, returning a 65-byte signature with NO prefix. */
  signHash(hash: Hex): Promise<Hex>;
  /** Privy access token (JWT) for authenticated UAPI viewer context. */
  getAccessToken(): Promise<string>;
}

/**
 * A node-sdk-free description of an XMTP signer. `client.ts` turns this into a
 * concrete `@xmtp/node-sdk` `Signer`. Keeping signing logic here (rather than in
 * `client.ts`) means it is unit-testable without loading the native binding.
 */
export interface XmtpSignerSpec {
  /** XMTP signer kind: `SCW` for the smart-wallet inbox, `EOA` for a raw key. */
  type: "SCW" | "EOA";
  /** The inbox-owning address (smart wallet for SCW, EOA address for EOA). */
  address: Address;
  /** Chain id used for SCW (ERC-1271) signature verification. */
  chainId: number;
  /** XMTP-facing message signer; returns the wrapped signature bytes. */
  signMessage(message: string): Promise<Uint8Array>;
}

/** A signer spec plus the token accessor for authenticated UAPI calls. */
export interface MessagingAuth {
  signerSpec: XmtpSignerSpec;
  /** Returns a Privy JWT for UAPI auth, or undefined in keyless/dev mode. */
  getApiToken(): Promise<string | undefined>;
}

/**
 * Production auth: the shared smart-wallet XMTP inbox, signing delegated to the
 * auth provider. Mirrors the web app's `useSmartWalletXmtpSigner`
 * (`frontend/apps/web/modules/messaging/client.ts`): hash → replay-safe hash →
 * raw-sign via the provider → wrap with owner index.
 */
export const createSmartWalletAuth = (
  provider: PrivyAuthProvider,
  chainId: number = base.id,
): MessagingAuth => {
  const address = provider.getSmartWalletAddress();

  const signMessage = async (message: string): Promise<Uint8Array> => {
    const replaySafeHash = toReplaySafeHash({
      chainId,
      address,
      hash: hashMessage(message),
    });
    const signature = await provider.signHash(replaySafeHash);
    const ownerIndex = getOwnerIndexForWallet({
      owners: provider.getOwners(),
      ownerAddress: provider.getOwnerAddress(),
    });
    return toBytes(wrapSignature({ ownerIndex, signature }));
  };

  return {
    signerSpec: { type: "SCW", address, chainId, signMessage },
    getApiToken: () => provider.getAccessToken(),
  };
};

/**
 * EOA auth: messages from a local EOA key as its *own* XMTP inbox (not the shared
 * smart-wallet inbox). The `zora dm` command uses smart-wallet auth, so this is
 * kept as a node-sdk-free primitive for testing the messaging client without
 * Privy. Standard EIP-191 signing — no smart-wallet wrapping; there is no Privy
 * JWT, so authenticated UAPI calls (e.g. the new-conversation gate) are skipped.
 */
export const createEoaAuth = (
  privateKey: Hex,
  chainId: number = base.id,
): MessagingAuth => {
  const account = privateKeyToAccount(privateKey);

  const signMessage = async (message: string): Promise<Uint8Array> => {
    const signature = await account.signMessage({ message });
    return toBytes(signature);
  };

  return {
    signerSpec: { type: "EOA", address: account.address, chainId, signMessage },
    getApiToken: async () => undefined,
  };
};
