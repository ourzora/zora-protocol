import { privateKeyToAccount } from "viem/accounts";
import {
  createPrivyAccount,
  refreshPrivySession,
  PrivySessionExpiredError,
  ZORA_PRIVY_APP_ID,
  DEFAULT_SIWE_ORIGIN,
  DEFAULT_SIWE_CHAIN_ID,
  type PrivyLinkedAccount,
} from "./privy.js";
import {
  getPrivySession,
  savePrivySession,
  type StoredPrivySession,
} from "./config.js";

export interface EnsurePrivySessionOptions {
  privateKey: `0x${string}`;
  /** Privy app id. Defaults to {@link ZORA_PRIVY_APP_ID}. */
  appId?: string;
  /** Origin the session is scoped to. Defaults to {@link DEFAULT_SIWE_ORIGIN}. */
  origin?: string;
  /** EVM chain id for the SIWE message. Defaults to {@link DEFAULT_SIWE_CHAIN_ID}. */
  chainId?: number;
}

/** How a session's current access token was obtained. */
export type PrivySessionSource = "cache" | "refresh" | "siwe";

export interface PrivySession {
  address: string;
  did: string;
  appId: string;
  origin: string;
  accessToken: string;
  /** Epoch ms at which the access token expires. */
  accessTokenExpiresAt: number;
  refreshToken?: string;
  identityToken?: string;
  /**
   * Linked accounts known for this session. Empty when only a cached access token
   * was reused, or when a refresh didn't return the user object — see
   * {@link linkedAccountsKnown}.
   */
  linkedAccounts: PrivyLinkedAccount[];
  /** Whether {@link linkedAccounts} reflects a fresh read from Privy (vs. an empty default). */
  linkedAccountsKnown: boolean;
  /** True only when this call ran a fresh SIWE that registered a brand-new Privy user. */
  isNewUser: boolean;
  source: PrivySessionSource;
}

/**
 * Re-authenticate this many ms before the access token's stated expiry, to absorb
 * clock skew and request latency rather than racing a token that expires mid-flight.
 */
const EXPIRY_SKEW_MS = 60_000;

function isFresh(expiresAt: number): boolean {
  return Date.now() < expiresAt - EXPIRY_SKEW_MS;
}

/**
 * Obtain a valid Privy access token for an EOA, minimizing SIWE calls (which Privy
 * rate-limits to ~60/week per app):
 *
 *   1. Reuse the cached access token while it is still valid.
 *   2. Otherwise exchange the cached refresh token at `/api/v1/sessions`.
 *   3. Otherwise (no cache, or the refresh was rejected) run the full SIWE handshake.
 *
 * The resulting session is persisted so later invocations start from step 1 or 2.
 */
export async function ensurePrivySession(
  opts: EnsurePrivySessionOptions,
): Promise<PrivySession> {
  const appId = opts.appId ?? ZORA_PRIVY_APP_ID;
  const origin = opts.origin ?? DEFAULT_SIWE_ORIGIN;
  const address = privateKeyToAccount(opts.privateKey).address;
  const cached = matchingSession(getPrivySession(), { address, appId, origin });

  // 1. Reuse a still-valid cached access token — no network call at all.
  if (cached && isFresh(cached.accessTokenExpiresAt)) {
    return fromStored(cached, "cache");
  }

  // 2. Exchange the refresh token for a new access token (doesn't touch the SIWE quota).
  if (cached?.refreshToken) {
    const refreshed = await tryRefresh(
      {
        refreshToken: cached.refreshToken,
        address: cached.address,
        did: cached.did,
        identityToken: cached.identityToken,
      },
      { appId, origin },
    );
    if (refreshed) return refreshed;
  }

  // 3. Fall back to a full SIWE sign-in.
  return siweSession({ ...opts, appId, origin });
}

/**
 * Re-read the session's linked accounts (e.g. while polling for the embedded wallet
 * that Privy provisions after profile creation). Prefers the refresh-token exchange,
 * which doesn't consume the SIWE quota, but only when that response actually carries
 * the user's linked accounts; otherwise re-authenticates with SIWE to read them.
 */
export async function refreshPrivyLinkedAccounts(
  session: PrivySession,
  opts: { privateKey: `0x${string}`; chainId?: number },
): Promise<PrivySession> {
  if (session.refreshToken) {
    const refreshed = await tryRefresh(
      {
        refreshToken: session.refreshToken,
        address: session.address,
        did: session.did,
        identityToken: session.identityToken,
      },
      { appId: session.appId, origin: session.origin },
    );
    // Use the refresh only if it told us the current linked accounts; otherwise a
    // SIWE re-auth is the only way to read them.
    if (refreshed?.linkedAccountsKnown) return refreshed;
  }
  return siweSession({
    privateKey: opts.privateKey,
    chainId: opts.chainId,
    appId: session.appId,
    origin: session.origin,
  });
}

/** Identity a refresh attempt needs: the token plus fields to carry forward. */
interface RefreshIdentity {
  refreshToken: string;
  address: string;
  did: string;
  identityToken?: string;
}

/**
 * Attempt a refresh-token exchange. Returns the new session on success (persisted),
 * or null when the token is rejected or the exchange otherwise fails, so the caller
 * can fall back to SIWE.
 */
async function tryRefresh(
  identity: RefreshIdentity,
  { appId, origin }: { appId: string; origin: string },
): Promise<PrivySession | null> {
  try {
    const refreshed = await refreshPrivySession({
      refreshToken: identity.refreshToken,
      appId,
      origin,
    });
    const session: PrivySession = {
      address: identity.address,
      did: refreshed.did ?? identity.did,
      appId,
      origin,
      accessToken: refreshed.accessToken,
      accessTokenExpiresAt: refreshed.accessTokenExpiresAt,
      refreshToken: refreshed.refreshToken,
      identityToken: refreshed.identityToken ?? identity.identityToken,
      linkedAccounts: refreshed.linkedAccounts ?? [],
      linkedAccountsKnown: refreshed.linkedAccounts !== undefined,
      isNewUser: false,
      source: "refresh",
    };
    persist(session);
    return session;
  } catch (err) {
    // Any refresh failure (rejected/expired token, network error, malformed
    // response) falls back to SIWE — the only remaining way to get a token. Warn
    // so an operator can see why SIWE calls (the rate-limited path) are happening,
    // rather than silently burning the ~60/week budget.
    const detail =
      err instanceof PrivySessionExpiredError
        ? `HTTP ${err.status}`
        : err instanceof Error
          ? err.message
          : String(err);
    console.warn(
      `Privy session refresh failed (${detail}); falling back to SIWE sign-in.`,
    );
    return null;
  }
}

/** Run the full SIWE handshake, persist the session, and return it. */
async function siweSession(
  opts: EnsurePrivySessionOptions & { appId: string; origin: string },
): Promise<PrivySession> {
  const privy = await createPrivyAccount({
    privateKey: opts.privateKey,
    appId: opts.appId,
    origin: opts.origin,
    chainId: opts.chainId ?? DEFAULT_SIWE_CHAIN_ID,
  });
  const session: PrivySession = {
    address: privy.address,
    did: privy.did,
    appId: opts.appId,
    origin: opts.origin,
    accessToken: privy.accessToken,
    accessTokenExpiresAt: privy.accessTokenExpiresAt,
    refreshToken: privy.refreshToken,
    identityToken: privy.identityToken,
    linkedAccounts: privy.linkedAccounts,
    linkedAccountsKnown: true,
    isNewUser: privy.isNewUser,
    source: "siwe",
  };
  persist(session);
  return session;
}

/**
 * A cached session only applies to the same (address, appId, origin) it was issued
 * for; a mismatch (e.g. the user switched keys) means the tokens don't apply.
 */
function matchingSession(
  stored: StoredPrivySession | undefined,
  id: { address: string; appId: string; origin: string },
): StoredPrivySession | undefined {
  if (!stored) return undefined;
  if (
    stored.address.toLowerCase() !== id.address.toLowerCase() ||
    stored.appId !== id.appId ||
    stored.origin !== id.origin
  ) {
    return undefined;
  }
  return stored;
}

function fromStored(
  stored: StoredPrivySession,
  source: PrivySessionSource,
): PrivySession {
  return {
    address: stored.address,
    did: stored.did,
    appId: stored.appId,
    origin: stored.origin,
    accessToken: stored.accessToken,
    accessTokenExpiresAt: stored.accessTokenExpiresAt,
    refreshToken: stored.refreshToken,
    identityToken: stored.identityToken,
    linkedAccounts: [],
    linkedAccountsKnown: false,
    isNewUser: false,
    source,
  };
}

function persist(session: PrivySession): void {
  savePrivySession({
    address: session.address,
    appId: session.appId,
    origin: session.origin,
    did: session.did,
    accessToken: session.accessToken,
    accessTokenExpiresAt: session.accessTokenExpiresAt,
    refreshToken: session.refreshToken,
    identityToken: session.identityToken,
  });
}
