import {
  createPublicClient,
  http,
  isAddressEqual,
  type Address,
  type Hex,
} from "viem";
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
import {
  getSmartWalletOwners,
  type SmartWalletOwner as OnChainOwner,
} from "../lib/account/smart-wallet.js";
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
  client: ChainClient,
): Promise<Address> {
  const configured = getSmartWalletAddress();
  if (configured) return configured;

  // Deriving the address requires the embedded owner. Without it — e.g. a cached
  // session whose linked accounts were never read and no persisted agent
  // identity — there's nothing to derive from, so onboarding hasn't happened here.
  if (!embedded) throw new Error(NEEDS_AGENT_CREATE);

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
 * Resolve the smart wallet's owner set — and thus the index we must wrap the
 * ERC-1271 signature with — from its ACTUAL on-chain layout, not a hardcoded
 * deploy-order guess. XMTP verifies the wrapped signature against the on-chain
 * owner at that index; wrapping the wrong index yields an invalid signature and
 * fails every fresh identity op (registering a new installation, revoking one) —
 * even though read/reuse paths, which don't re-sign, appear to work. A single
 * external owner at index 0 (rather than the assumed `[embedded@0, external@1]`)
 * is exactly what breaks under the old assumption.
 *
 * Delegates the on-chain read to the shared {@link getSmartWalletOwners} (the
 * same resolver buy/sell/post use), then maps to the `{ownerAddress, ownerIndex}`
 * shape XMTP signing needs — keeping only address (EOA) owners, since a passkey
 * owner holds an index but can't sign here.
 *
 * Best-effort: falls back to the deploy-order assumption if the read fails or
 * the signing EOA isn't found on-chain, so behavior never regresses below today.
 */
async function resolveOwners(args: {
  client: ChainClient;
  smartWallet: Address;
  external: Address;
  embedded: Address | undefined;
}): Promise<SmartWalletOwner[]> {
  const fallback: SmartWalletOwner[] = args.embedded
    ? [
        { ownerAddress: args.embedded, ownerIndex: 0 },
        { ownerAddress: args.external, ownerIndex: 1 },
      ]
    : [{ ownerAddress: args.external, ownerIndex: 1 }];

  try {
    const onChain = await getSmartWalletOwners(args.client, args.smartWallet);
    const owners: SmartWalletOwner[] = onChain
      .filter(
        (o): o is OnChainOwner & { address: Address } => o.address !== null,
      )
      .map((o) => ({ ownerAddress: o.address, ownerIndex: o.index }));
    // Only trust the on-chain set if it contains the EOA we actually sign with.
    if (owners.some((o) => isAddressEqual(o.ownerAddress, args.external))) {
      return owners;
    }
  } catch {
    // fall through to the deploy-order assumption
  }
  return fallback;
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

  const client =
    opts.client ??
    createPublicClient({
      chain: base,
      transport: http(opts.rpcUrl ?? DEFAULT_BASE_RPC),
    });

  const smartWallet = await resolveSmartWalletAddress(
    account.address,
    embedded,
    client,
  );

  // Wrap ERC-1271 signatures with the owner index the smart wallet actually uses
  // on-chain, not a deploy-order guess — see resolveOwners.
  const owners = await resolveOwners({
    client,
    smartWallet,
    external: account.address,
    embedded,
  });

  return {
    getSmartWalletAddress: () => smartWallet,
    getOwnerAddress: () => account.address,
    getOwners: () => owners,
    signHash: (hash: Hex) => account.sign({ hash }),
    getAccessToken: async () => session.accessToken,
  };
};
