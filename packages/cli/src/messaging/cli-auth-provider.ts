import { createPublicClient, http, type Address, type Hex } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { createPrivyAccount, findEmbeddedWallet } from "../lib/privy.js";
import {
  getSmartWalletAddress,
  saveSmartWalletAddress,
} from "../lib/config.js";
import { predictAddress, isDeployed } from "../lib/agent/smart-wallet.js";
import type { ChainClient } from "../lib/agent/zora-client.js";
import type { PrivyAuthProvider } from "./identity.js";
import type { SmartWalletOwner } from "./signer.js";

const DEFAULT_BASE_RPC = "https://mainnet.base.org";

const NEEDS_AGENT_CREATE =
  "No Zora smart wallet found for this key — run `zora agent create` first.";

export interface CliSmartWalletProviderOptions {
  /** 0x-prefixed EOA private key — the agent's external owner (owner #1). */
  privateKey: Hex;
  /** Base RPC URL, used only when the smart wallet address must be derived. */
  rpcUrl?: string;
  /** Privy app id. Defaults to the Zora production app via {@link createPrivyAccount}. */
  appId?: string;
  /** Injected chain client, for tests. Production derives one from `rpcUrl`. */
  client?: ChainClient;
}

/**
 * Resolve the shared XMTP inbox — the user's deployed Coinbase Smart Wallet.
 * Prefer the address persisted by `zora agent create`; otherwise derive it
 * deterministically from the owner set and confirm it is deployed. XMTP verifies
 * the smart wallet's ERC-1271 signature with an on-chain `eth_call` (there is no
 * ERC-6492 counterfactual path here), so an undeployed wallet cannot authenticate.
 */
async function resolveSmartWalletAddress(
  external: Address,
  embedded: Address,
  opts: CliSmartWalletProviderOptions,
): Promise<Address> {
  const configured = getSmartWalletAddress();
  if (configured) return configured;

  const client =
    opts.client ??
    createPublicClient({
      chain: base,
      transport: http(opts.rpcUrl ?? DEFAULT_BASE_RPC),
    });
  const predicted = await predictAddress(client, [embedded, external]);
  if (!(await isDeployed(client, predicted))) {
    throw new Error(
      "Your Zora smart wallet is not deployed yet — run `zora agent create` first.",
    );
  }
  // Persist it so the fast path (and the post-command DM check) can skip this
  // derivation next time.
  saveSmartWalletAddress(predicted);
  return predicted;
}

/**
 * Build the {@link PrivyAuthProvider} that authenticates `zora dm` as the user's
 * shared smart-wallet inbox — the concrete implementation of the contract
 * `createSmartWalletAuth` consumes.
 *
 * The CLI signs as the **external EOA** (owner #1) with `account.sign({ hash })`
 * — a raw 32-byte hash, 65-byte signature, no EIP-191 prefix. That EOA is a real
 * on-chain owner (the agent flow deploys the wallet with owners
 * `[embedded(0), external(1)]`), so its ERC-1271 signature is valid; unlike the
 * web app we do not need Privy server-side signing of the embedded wallet.
 */
export const createCliSmartWalletProvider = async (
  opts: CliSmartWalletProviderOptions,
): Promise<PrivyAuthProvider> => {
  const account = privateKeyToAccount(opts.privateKey);

  // Headless SIWE with the agent EOA — yields the Privy JWT for authenticated
  // UAPI calls and the linked accounts that expose the embedded (owner #0) wallet.
  const privy = await createPrivyAccount({
    privateKey: opts.privateKey,
    appId: opts.appId,
  });
  const embedded = findEmbeddedWallet(privy.linkedAccounts);
  if (!embedded) throw new Error(NEEDS_AGENT_CREATE);

  const smartWallet = await resolveSmartWalletAddress(
    account.address,
    embedded,
    opts,
  );

  // Owners in deploy order: index 0 = embedded (Privy), index 1 = external EOA.
  // Never return null — getOwnerIndexForWallet would then fall back to index 0
  // while we sign with the external key, producing an invalid ERC-1271 signature.
  const owners: SmartWalletOwner[] = [
    { ownerAddress: embedded, ownerIndex: 0 },
    { ownerAddress: account.address, ownerIndex: 1 },
  ];

  return {
    getSmartWalletAddress: () => smartWallet,
    getOwnerAddress: () => account.address,
    getOwners: () => owners,
    signHash: (hash: Hex) => account.sign({ hash }),
    getAccessToken: async () => privy.accessToken,
  };
};
