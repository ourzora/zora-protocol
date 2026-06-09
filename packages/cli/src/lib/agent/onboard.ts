import { createPublicClient, http, type Address } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import {
  createPrivyAccount,
  findEmbeddedWallet,
  type PrivyAccount,
} from "../privy.js";
import { createAgentProfile } from "./profile.js";
import { provisionSmartWallet } from "./smart-wallet.js";

/** A progress step the caller can render. */
export type OnboardStep = "privy" | "profile" | "embedded" | "smartWallet";

export interface OnboardOptions {
  privateKey: `0x${string}`;
  appId?: string;
  origin?: string;
  chainId?: number;
  /** Base RPC URL (defaults to the public endpoint). */
  rpcUrl?: string;
  /** Max attempts to poll for the embedded wallet after profile creation. */
  embeddedAttempts?: number;
  onProgress?: (step: OnboardStep, detail: string) => void;
  sleep?: (ms: number) => Promise<void>;
}

export interface OnboardResult {
  address: Address;
  did: string;
  accessToken: string;
  username: string;
  embedded: Address;
  smartWallet: Address;
  isNewUser: boolean;
}

const DEFAULT_BASE_RPC = "https://mainnet.base.org";

/**
 * Stand up a Zora agent identity from an EOA, with no human interaction:
 * Privy account → Zora profile → smart wallet. Every on-chain step is
 * paymaster-sponsored, so the agent needs no ETH. (The creator coin and first
 * post build on this.)
 */
export async function onboardAgent(
  opts: OnboardOptions,
): Promise<OnboardResult> {
  const sleep =
    opts.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  const progress = opts.onProgress ?? (() => {});
  const account = privateKeyToAccount(opts.privateKey);
  const client = createPublicClient({
    chain: base,
    transport: http(opts.rpcUrl ?? DEFAULT_BASE_RPC),
  });

  const signIn = (): Promise<PrivyAccount> =>
    createPrivyAccount({
      privateKey: opts.privateKey,
      appId: opts.appId,
      origin: opts.origin,
      chainId: opts.chainId,
    });

  // 1. Privy account (headless SIWE).
  progress("privy", "signing in with the agent EOA");
  let privy = await signIn();
  // Capture is_new_user from the *first* sign-in. Privy only sets it on initial
  // registration; the embedded-wallet poll below re-authenticates (always as a
  // returning user), which would otherwise clobber it to false for new agents.
  const isNewUser = privy.isNewUser;

  // 2. Profile — idempotent, and provisions the embedded wallet server-side.
  progress("profile", "creating the Zora profile");
  const profile = await createAgentProfile(privy.accessToken);

  // 3. Wait for the embedded wallet to appear, re-authenticating to refresh.
  progress("embedded", "waiting for the embedded wallet");
  let embedded = findEmbeddedWallet(privy.linkedAccounts);
  const maxAttempts = opts.embeddedAttempts ?? 8;
  for (let attempt = 0; !embedded && attempt < maxAttempts; attempt++) {
    await sleep(3000);
    privy = await signIn();
    embedded = findEmbeddedWallet(privy.linkedAccounts);
  }
  if (!embedded) {
    throw new Error(
      "The embedded wallet was not provisioned after creating the profile.",
    );
  }

  // 4. Smart wallet (deploy + resolve + link + owner-sync).
  progress("smartWallet", "provisioning the smart wallet");
  const smartWallet = await provisionSmartWallet({
    token: privy.accessToken,
    client,
    embedded,
    external: account.address,
    sleep,
  });

  return {
    address: account.address,
    did: privy.did,
    accessToken: privy.accessToken,
    username: profile.username,
    embedded,
    smartWallet: smartWallet.address,
    isNewUser,
  };
}
