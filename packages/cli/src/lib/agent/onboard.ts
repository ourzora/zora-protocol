import { createPublicClient, http, type Address } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import {
  createPrivyAccount,
  findEmbeddedWallet,
  type PrivyAccount,
} from "../privy.js";
import { createAgentProfile } from "./profile.js";
import { updateAgentProfile } from "./update-profile.js";
import type { AvatarFile } from "./avatar.js";
import { ipfsUpload } from "./zora-client.js";
import { provisionSmartWallet } from "./smart-wallet.js";
import { createCreatorCoin } from "./coin.js";
import { createFirstPost } from "./post.js";

/** A progress step the caller can render. */
export type OnboardStep =
  | "privy"
  | "profile"
  | "embedded"
  | "smartWallet"
  | "coin"
  | "post";

export interface OnboardOptions {
  privateKey: `0x${string}`;
  appId?: string;
  origin?: string;
  chainId?: number;
  /** Base RPC URL (defaults to the public endpoint). */
  rpcUrl?: string;
  /** Simulate the coin + post instead of minting them. */
  dryRun?: boolean;
  skipCoin?: boolean;
  skipPost?: boolean;
  /**
   * Optional profile fields to apply at creation. Each is independent: omit one
   * to keep Zora's auto-assigned value. `username` is availability-checked
   * server-side (and also sets the display name); `bio` of `""` clears the
   * default bio; `avatar` is a local image, already read by the caller, that is
   * uploaded to IPFS during onboarding.
   */
  username?: string;
  bio?: string;
  avatar?: AvatarFile;
  /**
   * First-post content. The post is published only when both `caption` and
   * `postImage` are provided (and `skipPost` is not set): `caption` is the big
   * centered meme text, `postImage` is the background photo (already read by the
   * caller). `postTitle`/`postDescription` set the coin metadata, each defaulting
   * to the caption. The footer handle is derived from the agent's username.
   */
  caption?: string;
  postImage?: AvatarFile;
  postTitle?: string;
  postDescription?: string;
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
  /** The profile's avatar URI (the chosen one if `--avatar` was set, else the auto-assigned default). */
  avatarUri?: string;
  embedded: Address;
  smartWallet: Address;
  isNewUser: boolean;
  dryRun: boolean;
  /** The agent's Zora profile URL. Always set once the account exists. */
  profileUrl: string;
  coin?: {
    hash?: string;
    sponsored: boolean;
    simulation: string;
    url?: string;
  };
  /**
   * Set when the (non-fatal) creator-coin step failed *after* the account was
   * already created. The identity above is still valid and worth reporting.
   */
  coinError?: string;
  post?: {
    hash?: string;
    caption: string;
    ticker: string;
    sponsored: boolean;
    simulation: string;
    imageUri: string;
    contractUri: string;
    coinAddress?: Address;
    /**
     * A link to the first post. The precise content-coin URL when the coin
     * address resolved, otherwise the agent's profile URL (where the post is
     * visible) so a link is always available. `undefined` only on a dry run,
     * where nothing was minted. Check `coinAddress` to tell the two apart.
     */
    url?: string;
  };
  /**
   * Set when the (non-fatal) first-post step failed *after* the account was
   * already created. The identity above is still valid and worth reporting.
   */
  postError?: string;
}

const DEFAULT_BASE_RPC = "https://mainnet.base.org";
const ZORA_BASE_URL = "https://zora.co";

/**
 * Stand up a complete Zora agent identity from an EOA, with no human interaction:
 * Privy account → profile → smart wallet → creator coin → first post. Every
 * on-chain step is paymaster-sponsored, so the agent needs no ETH. Returns the
 * created identity; with `dryRun`, the coin + post are simulated, not minted.
 *
 * The account (Privy + profile + smart wallet) is the core deliverable: a
 * failure in any of those throws. The creator coin and first post run *after*
 * the account exists and are best-effort — if either fails, its error is
 * recorded on `coinError` / `postError` and onboarding still resolves with the
 * full identity (and its profile link) rather than discarding everything.
 */
export async function onboardAgent(
  opts: OnboardOptions,
): Promise<OnboardResult> {
  const sleep =
    opts.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  const progress = opts.onProgress ?? (() => {});
  const dryRun = Boolean(opts.dryRun);
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
  let profile = await createAgentProfile(privy.accessToken);

  // 2b. Apply any caller-chosen profile fields (username / bio / avatar). This
  //     is optional — with none provided the auto-assigned profile is kept. We
  //     do it here, before the smart wallet, coin, and first post, so that a
  //     taken username fails fast (before those steps run) and every downstream
  //     link and the coin's metadata use the chosen handle.
  if (
    opts.username !== undefined ||
    opts.bio !== undefined ||
    opts.avatar !== undefined
  ) {
    const chosen = [
      opts.username !== undefined ? "username" : undefined,
      opts.bio !== undefined ? "bio" : undefined,
      opts.avatar ? "avatar" : undefined,
    ].filter((field): field is string => field !== undefined);
    progress(
      "profile",
      `applying the chosen ${new Intl.ListFormat("en", { type: "conjunction" }).format(chosen)}`,
    );

    // Apply the text fields (username / bio) first: it's a cheap call that also
    // validates the username's availability, so a taken handle fails here —
    // before the (potentially slow) IPFS avatar upload runs.
    if (opts.username !== undefined || opts.bio !== undefined) {
      profile = await updateAgentProfile(privy.accessToken, {
        username: opts.username,
        bio: opts.bio,
      });
    }
    // Then upload and apply the avatar.
    if (opts.avatar) {
      const avatarUri = await ipfsUpload(
        privy.accessToken,
        opts.avatar.filename,
        opts.avatar.bytes,
        opts.avatar.mimeType,
      );
      profile = await updateAgentProfile(privy.accessToken, { avatarUri });
    }
  }

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

  const result: OnboardResult = {
    address: account.address,
    did: privy.did,
    accessToken: privy.accessToken,
    username: profile.username,
    avatarUri: profile.avatarUri,
    embedded,
    smartWallet: smartWallet.address,
    isNewUser,
    dryRun,
    profileUrl: `${ZORA_BASE_URL}/@${profile.username}`,
  };

  // 5. Creator coin (best-effort — the account already exists at this point).
  if (!opts.skipCoin) {
    progress(
      "coin",
      dryRun ? "simulating the creator coin" : "minting the creator coin",
    );
    try {
      const coin = await createCreatorCoin({
        token: privy.accessToken,
        account,
        client,
        dryRun,
      });
      result.coin = {
        hash: coin.submitted?.hash,
        sponsored: coin.sponsored,
        simulation: coin.simulation,
        url: dryRun
          ? undefined
          : `${ZORA_BASE_URL}/@${profile.username}/creator-coin`,
      };
    } catch (err) {
      result.coinError = errorMessage(err);
    }
  }

  // 6. First post (best-effort — the account already exists at this point).
  // Published only when the caller supplied both a caption and a background
  // image; otherwise there's nothing to render, so the step is skipped.
  if (!opts.skipPost && opts.caption && opts.postImage) {
    progress(
      "post",
      dryRun ? "simulating the first post" : "publishing the first post",
    );
    try {
      const post = await createFirstPost({
        token: privy.accessToken,
        account,
        client,
        smartWallet: smartWallet.address,
        owners: smartWallet.owners,
        dryRun,
        caption: opts.caption,
        image: {
          bytes: opts.postImage.bytes,
          mimeType: opts.postImage.mimeType,
        },
        handle: `zora.co/${result.username}`,
        title: opts.postTitle,
        description: opts.postDescription,
        // Forward the injected clock so the receipt-poll loop is controllable
        // from onboardAgent (tests inject a no-op sleep; prod uses setTimeout).
        sleep,
      });
      result.post = {
        hash: post.submitted?.hash,
        caption: post.caption,
        ticker: post.ticker,
        sponsored: post.sponsored,
        simulation: post.simulation,
        imageUri: post.imageUri,
        contractUri: post.contractUri,
        coinAddress: post.coinAddress,
        // Always expose a link to the first post once it's minted: the precise
        // content-coin URL when the address resolved, else the profile (where
        // the post is visible) so the link is never silently dropped. On a dry
        // run nothing was minted, so there's no link.
        url: dryRun
          ? undefined
          : post.coinAddress
            ? `${ZORA_BASE_URL}/coin/base:${post.coinAddress.toLowerCase()}`
            : result.profileUrl,
      };
    } catch (err) {
      result.postError = errorMessage(err);
    }
  }

  return result;
}

/** Extract a human-readable message from an unknown thrown value. */
function errorMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
