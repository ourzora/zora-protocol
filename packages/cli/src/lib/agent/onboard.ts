import { createPublicClient, http, type Address } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { mapAgentHarnessToUapi, type AgentHarness } from "../agent-harness.js";
import { findEmbeddedWallet } from "../privy.js";
import {
  ensurePrivySession,
  refreshPrivyLinkedAccounts,
} from "../privy-session.js";
import { createAgentProfile } from "./profile.js";
import { updateAgentProfile } from "./update-profile.js";
import type { AvatarFile } from "./avatar.js";
import { ipfsUpload } from "./zora-client.js";
import { provisionSmartWallet } from "./smart-wallet.js";
import { createCreatorCoin } from "./coin.js";
import { createFirstPost } from "./post.js";
import { createApiKey } from "./api-key.js";
import { getConfigPath, saveApiKey } from "../config.js";
import { fsErrorMessage } from "../errors.js";

/** A progress step the caller can render. */
export type OnboardStep =
  | "privy"
  | "profile"
  | "apiKey"
  | "embedded"
  | "smartWallet"
  | "coin"
  | "post";

export interface OnboardOptions {
  privateKey: `0x${string}`;
  appId?: string;
  origin?: string;
  chainId?: number;
  /** Local agent harness detected from the working directory, when present. */
  agentHarness?: AgentHarness;
  /** Base RPC URL (defaults to the public endpoint). */
  rpcUrl?: string;
  /** Simulate the coin + post instead of minting them. */
  dryRun?: boolean;
  /** Skip minting the agent's creator coin during onboarding. */
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
   * to the caption; `postTicker` forces the coin's ticker (validated; defaults to
   * one derived from the title). The footer handle is derived from the username.
   */
  caption?: string;
  postImage?: AvatarFile;
  postTitle?: string;
  postDescription?: string;
  postTicker?: string;
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
 * Stand up a Zora agent identity from an EOA, with no human interaction:
 * Privy account → profile → smart wallet → creator coin. The creator coin is
 * minted automatically unless `skipCoin` is set; the first post is published
 * when `caption` + `postImage` are supplied. Every on-chain step is
 * paymaster-sponsored, so the agent needs no ETH. Returns the created identity;
 * with `dryRun`, the coin + post are simulated, not minted.
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

  // 1. Privy session (cached access token, refresh, or headless SIWE).
  progress("privy", "signing in with the agent EOA");
  let session = await ensurePrivySession({
    privateKey: opts.privateKey,
    appId: opts.appId,
    origin: opts.origin,
    chainId: opts.chainId,
  });
  // Capture is_new_user from the *first* sign-in. Privy only sets it when SIWE
  // registers a brand-new user; the embedded-wallet poll below re-fetches the
  // session (always as a returning user), which would otherwise clobber it.
  const isNewUser = session.isNewUser;

  // 2. Profile — idempotent, and provisions the embedded wallet server-side.
  progress("profile", "creating the Zora profile");
  let profile = await createAgentProfile(session.accessToken);

  // 2a. Create an API key for the agent.
  progress("apiKey", "creating an API key");
  const apiKey = await createApiKey(session.accessToken, "AGENT_API_KEY");
  try {
    saveApiKey(apiKey);
  } catch (err) {
    throw new Error(
      `Failed to save API key: ${fsErrorMessage(err, getConfigPath())}`,
    );
  }

  // 2b. Apply any caller-chosen profile fields (username / bio / avatar). This
  //     is optional — with none provided the auto-assigned profile is kept. We
  //     do it here, before the smart wallet, coin, and first post, so that a
  //     taken username fails fast (before those steps run) and every downstream
  //     link and the coin's metadata use the chosen handle.
  if (
    opts.username !== undefined ||
    opts.bio !== undefined ||
    opts.avatar !== undefined ||
    opts.agentHarness !== undefined
  ) {
    const chosen = [
      opts.username !== undefined ? "username" : undefined,
      opts.bio !== undefined ? "bio" : undefined,
      opts.avatar ? "avatar" : undefined,
      opts.agentHarness !== undefined ? "agent harness" : undefined,
    ].filter((field): field is string => field !== undefined);
    progress(
      "profile",
      `applying the chosen ${new Intl.ListFormat("en", { type: "conjunction" }).format(chosen)}`,
    );

    // Apply the text fields (username / bio) first: it's a cheap call that also
    // validates the username's availability, so a taken handle fails here —
    // before the (potentially slow) IPFS avatar upload runs.
    if (
      opts.username !== undefined ||
      opts.bio !== undefined ||
      opts.agentHarness !== undefined
    ) {
      profile = await updateAgentProfile(session.accessToken, {
        username: opts.username,
        bio: opts.bio,
        ...(opts.agentHarness
          ? { agentHarness: mapAgentHarnessToUapi(opts.agentHarness) }
          : {}),
      });
    }
    // Then upload and apply the avatar.
    if (opts.avatar) {
      const avatarUri = await ipfsUpload(
        session.accessToken,
        opts.avatar.filename,
        opts.avatar.bytes,
        opts.avatar.mimeType,
      );
      profile = await updateAgentProfile(session.accessToken, { avatarUri });
    }
  }

  // 3. Wait for the embedded wallet to appear, refreshing the session to re-read
  //    the linked accounts (refresh-first, so we don't burn the SIWE quota).
  progress("embedded", "waiting for the embedded wallet");
  let embedded = findEmbeddedWallet(session.linkedAccounts);
  const maxAttempts = opts.embeddedAttempts ?? 8;
  for (let attempt = 0; !embedded && attempt < maxAttempts; attempt++) {
    await sleep(3000);
    session = await refreshPrivyLinkedAccounts(session, {
      privateKey: opts.privateKey,
      chainId: opts.chainId,
    });
    embedded = findEmbeddedWallet(session.linkedAccounts);
  }
  if (!embedded) {
    throw new Error(
      "The embedded wallet was not provisioned after creating the profile.",
    );
  }

  // 4. Smart wallet (deploy + resolve + link + owner-sync).
  progress("smartWallet", "provisioning the smart wallet");
  const smartWallet = await provisionSmartWallet({
    token: session.accessToken,
    client,
    embedded,
    external: account.address,
    sleep,
  });

  const result: OnboardResult = {
    address: account.address,
    did: session.did,
    accessToken: session.accessToken,
    username: profile.username,
    avatarUri: profile.avatarUri,
    embedded,
    smartWallet: smartWallet.address,
    isNewUser,
    dryRun,
    profileUrl: `${ZORA_BASE_URL}/@${profile.username}`,
  };

  // 5. Creator coin — automatic (best-effort — the account already exists at this
  //    point). Pass `skipCoin` to skip, or create it after the fact with
  //    `createAgentCoin`.
  if (!opts.skipCoin) {
    progress(
      "coin",
      dryRun ? "simulating the creator coin" : "minting the creator coin",
    );
    try {
      const coin = await createCreatorCoin({
        token: session.accessToken,
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
        token: session.accessToken,
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
        ticker: opts.postTicker,
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

export interface CreateAgentCoinOptions {
  privateKey: `0x${string}`;
  appId?: string;
  origin?: string;
  chainId?: number;
  /** Base RPC URL (defaults to the public endpoint). */
  rpcUrl?: string;
  /** Simulate the creator coin instead of minting it. */
  dryRun?: boolean;
  onProgress?: (step: OnboardStep, detail: string) => void;
}

export interface AgentCoinResult {
  address: Address;
  did: string;
  accessToken: string;
  username: string;
  /** The agent's Zora profile URL. */
  profileUrl: string;
  dryRun: boolean;
  coin: {
    hash?: string;
    sponsored: boolean;
    simulation: string;
    url?: string;
  };
}

/**
 * Create the agent's creator coin for an account that already exists — the
 * companion to onboarding with `skipCoin` set. Signs in (reusing the cached
 * Privy session when present), resolves the agent's profile (idempotent — the
 * coin's name/ticker come from the handle server-side), then mints the sponsored
 * creator coin. The smart wallet that executes the deploy is resolved server-side
 * from the session, so no local re-provisioning is needed. With `dryRun`, stops
 * after a successful simulation.
 */
export async function createAgentCoin(
  opts: CreateAgentCoinOptions,
): Promise<AgentCoinResult> {
  const progress = opts.onProgress ?? (() => {});
  const dryRun = Boolean(opts.dryRun);
  const account = privateKeyToAccount(opts.privateKey);
  const client = createPublicClient({
    chain: base,
    transport: http(opts.rpcUrl ?? DEFAULT_BASE_RPC),
  });

  progress("privy", "signing in with the agent EOA");
  const session = await ensurePrivySession({
    privateKey: opts.privateKey,
    appId: opts.appId,
    origin: opts.origin,
    chainId: opts.chainId,
  });

  // The creator coin is tied to the agent's profile (its name/ticker are derived
  // from the handle server-side). createAgentProfile is idempotent, so on an
  // existing agent this just resolves the profile and gives us the handle.
  progress("profile", "resolving the Zora profile");
  const profile = await createAgentProfile(session.accessToken);

  progress(
    "coin",
    dryRun ? "simulating the creator coin" : "minting the creator coin",
  );
  const coin = await createCreatorCoin({
    token: session.accessToken,
    account,
    client,
    dryRun,
  });

  return {
    address: account.address,
    did: session.did,
    accessToken: session.accessToken,
    username: profile.username,
    profileUrl: `${ZORA_BASE_URL}/@${profile.username}`,
    dryRun,
    coin: {
      hash: coin.submitted?.hash,
      sponsored: coin.sponsored,
      simulation: coin.simulation,
      url: dryRun
        ? undefined
        : `${ZORA_BASE_URL}/@${profile.username}/creator-coin`,
    },
  };
}
