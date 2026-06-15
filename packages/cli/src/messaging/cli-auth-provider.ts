import { createPublicClient, http, type Address, type Hex } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { findEmbeddedWallet } from "../lib/privy.js";
import { ensurePrivySession, type PrivySession } from "../lib/privy-session.js";
import {
  getAgentWallet,
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
  /** Privy app id. Defaults to the Zora production app via {@link ensurePrivySession}. */
  appId?: string;
  /** Injected chain client, for tests. Production derives one from `rpcUrl`. */
  client?: ChainClient;
}

/**
 * Resolve the Privy embedded wallet — smart-wallet owner #0. Prefer the linked
 * accounts on the session, but only when this run actually read them: a SIWE
 * sign-in always does, a refresh-token exchange does only when Privy returns the
 * user object, and a cached-token reuse never does (see
 * {@link PrivySession.linkedAccountsKnown}). When they're absent, fall back to
 * the embedded address `zora agent create` persisted. May be undefined — the
 * only step that strictly needs it is deriving a smart wallet address that isn't
 * already configured.
 */
function resolveEmbeddedWallet(session: PrivySession): Address | undefined {
  if (session.linkedAccountsKnown) {
    const fromSession = findEmbeddedWallet(session.linkedAccounts);
    if (fromSession) return fromSession;
  }
  return getAgentWallet()?.embeddedWalletAddress;
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
  embedded: Address | undefined,
  opts: CliSmartWalletProviderOptions,
): Promise<Address> {
  const configured = getSmartWalletAddress();
  if (configured) return configured;

  // Deriving the address requires the embedded owner. Without it — e.g. a cached
  // session whose linked accounts were never read and no persisted agent
  // identity — there's nothing to derive from, so onboarding hasn't happened here.
  if (!embedded) throw new Error(NEEDS_AGENT_CREATE);

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

  // Reuse the cached Privy session, or refresh it via the long-lived refresh
  // token, falling back to a full SIWE sign-in only when neither is available.
  // SIWE is rate-limited (~60/week per app), so re-running it on every `zora dm`
  // invocation — and on the background new-DM check that follows other commands —
  // would quickly exhaust that budget. See {@link ensurePrivySession}.
  const session = await ensurePrivySession({
    privateKey: opts.privateKey,
    appId: opts.appId,
  });
  const embedded = resolveEmbeddedWallet(session);

  const smartWallet = await resolveSmartWalletAddress(
    account.address,
    embedded,
    opts,
  );

  // Owners in deploy order: index 0 = embedded (Privy), index 1 = external EOA.
  // We sign as the external EOA, so the index lookup only needs to *find* it;
  // include the embedded owner when known so the set is accurate. The list must
  // always contain the external EOA — getOwnerIndexForWallet otherwise falls back
  // to index 0 while we sign with the external key, producing an invalid
  // ERC-1271 signature.
  const owners: SmartWalletOwner[] = embedded
    ? [
        { ownerAddress: embedded, ownerIndex: 0 },
        { ownerAddress: account.address, ownerIndex: 1 },
      ]
    : [{ ownerAddress: account.address, ownerIndex: 1 }];

  return {
    getSmartWalletAddress: () => smartWallet,
    getOwnerAddress: () => account.address,
    getOwners: () => owners,
    signHash: (hash: Hex) => account.sign({ hash }),
    getAccessToken: async () => session.accessToken,
  };
};
