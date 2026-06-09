import { createPrivyAccount } from "../privy.js";
import { createAgentProfile } from "./profile.js";

/** A progress step the caller can render. */
export type OnboardStep = "privy" | "profile";

export interface OnboardOptions {
  privateKey: `0x${string}`;
  appId?: string;
  origin?: string;
  chainId?: number;
  onProgress?: (step: OnboardStep, detail: string) => void;
}

export interface OnboardResult {
  address: string;
  did: string;
  accessToken: string;
  username: string;
  isNewUser: boolean;
}

/**
 * Stand up a Zora agent identity from an EOA, with no human interaction:
 * Privy account → Zora profile. (Later steps — smart wallet, creator coin, and
 * first post — build on this.)
 */
export async function onboardAgent(
  opts: OnboardOptions,
): Promise<OnboardResult> {
  const progress = opts.onProgress ?? (() => {});
  const signIn = () =>
    createPrivyAccount({
      privateKey: opts.privateKey,
      appId: opts.appId,
      origin: opts.origin,
      chainId: opts.chainId,
    });

  // 1. Privy account (headless SIWE).
  progress("privy", "signing in with the agent EOA");
  const privy = await signIn();

  // 2. Profile — idempotent, and provisions the embedded wallet server-side.
  progress("profile", "creating the Zora profile");
  const profile = await createAgentProfile(privy.accessToken);

  return {
    address: privy.address,
    did: privy.did,
    accessToken: privy.accessToken,
    username: profile.username,
    isNewUser: privy.isNewUser,
  };
}
