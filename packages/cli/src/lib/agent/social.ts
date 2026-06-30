import { graphqlRequest } from "./zora-client.js";

// The no-arg `updateSocials` mutation the web app runs after a social link: it
// reads the authenticated user's Privy-linked accounts (server-side) and syncs
// them onto the Zora profile, which is what makes a freshly-linked social show
// up on profile pages across web and mobile.
const SYNC_SOCIALS_MUTATION =
  "mutation SyncSocials { updateSocials { socialAccounts { forceUnlinkedSocials twitter { username } tiktok { username } instagram { username } farcaster { username } } } }";

/** Platforms the Zora profile can carry (a superset of what the CLI can link). */
export type SocialPlatform = "twitter" | "tiktok" | "instagram" | "farcaster";

export type SocialUsernames = Partial<Record<SocialPlatform, string>>;

/** Human-friendly labels for the profile's social platforms, for CLI output. */
export const SOCIAL_PLATFORM_LABELS: Record<SocialPlatform, string> = {
  twitter: "Twitter/X",
  tiktok: "TikTok",
  instagram: "Instagram",
  farcaster: "Farcaster",
};

export interface SyncedSocialAccounts {
  /**
   * Platforms the backend refused to keep linked, as `ESocialPlatform` enum
   * values (uppercase, e.g. `"INSTAGRAM"`). A platform appears here when it was
   * linked recently and is within the provider's re-link cooldown.
   */
  forceUnlinkedSocials: string[];
  /** The synced username per platform, when the profile now has one. */
  usernames: SocialUsernames;
}

export interface SyncSocialsOptions {
  /** Retry attempts — the backend reads the just-linked account from Privy, which can lag. */
  attempts?: number;
  sleep?: (ms: number) => Promise<void>;
  /**
   * When set, keep retrying until this platform's username is present (or it is
   * force-unlinked, a terminal cooldown state). Right after `oauth/link` the
   * backend can return `socialAccounts` before the new account propagates, with
   * its username still null; this avoids reporting success in that window. Omit
   * (e.g. for `list`) to return as soon as `socialAccounts` is present.
   */
  awaitPlatform?: SocialPlatform;
}

/**
 * Sync the Zora profile's social accounts from the authenticated user's
 * Privy-linked accounts. Mirrors the web app's post-link `updateSocials` call;
 * without it a social linked via `oauth/link` stays in Privy but never appears
 * on the Zora profile.
 *
 * Retries a few times because the link the backend reads from Privy is
 * eventually-consistent right after `oauth/link`.
 */
export async function syncSocials(
  token: string,
  opts: SyncSocialsOptions = {},
): Promise<SyncedSocialAccounts> {
  const attempts = opts.attempts ?? 3;
  const sleep =
    opts.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));

  let lastError = "no socialAccounts returned";
  let lastResult: SyncedSocialAccounts | undefined;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const { data, errors, status } = await graphqlRequest(
        token,
        SYNC_SOCIALS_MUTATION,
        "SyncSocials",
      );
      const accounts = data?.updateSocials?.socialAccounts;
      if (accounts) {
        const usernames: SocialUsernames = {};
        if (accounts.twitter?.username)
          usernames.twitter = accounts.twitter.username;
        if (accounts.tiktok?.username)
          usernames.tiktok = accounts.tiktok.username;
        if (accounts.instagram?.username)
          usernames.instagram = accounts.instagram.username;
        if (accounts.farcaster?.username)
          usernames.farcaster = accounts.farcaster.username;
        const result: SyncedSocialAccounts = {
          forceUnlinkedSocials: Array.isArray(accounts.forceUnlinkedSocials)
            ? accounts.forceUnlinkedSocials
            : [],
          usernames,
        };
        // Without awaitPlatform, any socialAccounts response is final. With it,
        // keep retrying until that platform's username lands — unless it was
        // force-unlinked (`ESocialPlatform` is the uppercased platform key),
        // which is terminal and won't resolve by waiting.
        const awaiting = opts.awaitPlatform;
        const settled =
          !awaiting ||
          result.usernames[awaiting] !== undefined ||
          result.forceUnlinkedSocials.includes(awaiting.toUpperCase());
        if (settled) return result;
        lastResult = result;
      } else {
        lastError = errors?.[0]?.message ?? `HTTP ${status}`;
      }
    } catch (err) {
      // A thrown graphqlRequest (e.g. DNS/TCP failure) is transient too — treat
      // it like a failed attempt so retries cover network errors, not just
      // empty/error responses. The final attempt's error is surfaced below.
      lastError = err instanceof Error ? err.message : String(err);
    }
    if (attempt < attempts - 1) await sleep(1000);
  }
  // Retries exhausted: return the best response we saw (e.g. socialAccounts
  // present but the awaited username never propagated — the caller reports it as
  // not-yet-synced), or throw if no socialAccounts ever came back.
  if (lastResult) return lastResult;
  throw new Error(`updateSocials failed: ${lastError}`);
}
