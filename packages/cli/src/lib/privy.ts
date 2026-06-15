import { privateKeyToAccount } from "viem/accounts";
import { createSiweMessage } from "viem/siwe";

/**
 * The Zora production Privy application id.
 *
 * An agent's Privy session is only accepted by the Zora backend if the user
 * belongs to this app, so this is the default for {@link createPrivyAccount}.
 */
export const ZORA_PRIVY_APP_ID = "clpgf04wn04hnkw0fv1m11mnb";

/** Default origin the SIWE message is scoped to (an allowed origin on the app). */
export const DEFAULT_SIWE_ORIGIN = "https://zora.com";

/** Base mainnet — the default chain for the SIWE message. */
export const DEFAULT_SIWE_CHAIN_ID = 8453;

const PRIVY_AUTH_BASE = "https://auth.privy.io";

// Privy's WAF rejects non-browser User-Agents (e.g. the default Node fetch UA),
// so we present as a browser for the auth.privy.io calls.
const BROWSER_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

export interface CreatePrivyAccountOptions {
  /** 0x-prefixed EOA private key used to sign the SIWE message. */
  privateKey: `0x${string}`;
  /** Privy app id. Defaults to {@link ZORA_PRIVY_APP_ID}. */
  appId?: string;
  /** Origin the SIWE message is scoped to. Defaults to {@link DEFAULT_SIWE_ORIGIN}. */
  origin?: string;
  /** EVM chain id for the SIWE message. Defaults to {@link DEFAULT_SIWE_CHAIN_ID}. */
  chainId?: number;
  /**
   * Privy `walletClientType` sent to `siwe/authenticate`. Defaults to `"metamask"`
   * — mimicking a browser MetaMask client to satisfy Privy's WAF. Override if
   * Privy's tolerance for that from a non-browser context changes.
   */
  walletClientType?: string;
  /** Privy `connectorType` sent to `siwe/authenticate`. Defaults to `"injected"`. */
  connectorType?: string;
  /** Privy auth API base. Override only for testing. */
  authBase?: string;
}

/** A Privy linked account (an external or embedded wallet, OAuth login, etc.). */
export interface PrivyLinkedAccount {
  type?: string;
  address?: string;
  wallet_client_type?: string;
}

export interface PrivyAccount {
  /** The EOA address that signed in. */
  address: string;
  /** The Privy user DID (`did:privy:...`). */
  did: string;
  /**
   * Short-lived Privy access token (a JWT, ~1h). Send it as
   * `Authorization: Bearer <accessToken>` to the Zora GraphQL/tRPC endpoints.
   */
  accessToken: string;
  /** Epoch ms at which {@link accessToken} expires, read from its JWT `exp` claim. */
  accessTokenExpiresAt: number;
  /**
   * Long-lived refresh token, read from the `privy-refresh-token` Set-Cookie that
   * `siwe/authenticate` returns (it is not in the JSON body). Exchange it at
   * `/api/v1/sessions` — see {@link refreshPrivySession} — for a fresh access token
   * without re-running SIWE, which Privy rate-limits to ~60 calls/week. Undefined if
   * Privy did not set the cookie.
   */
  refreshToken?: string;
  /** Privy identity token, when returned. */
  identityToken?: string;
  /** True when this call created a brand-new Privy user (vs. re-authenticating). */
  isNewUser: boolean;
  /** The Privy user's linked accounts (wallets, etc.). */
  linkedAccounts: PrivyLinkedAccount[];
  /**
   * The session `Cookie` header value from the SIWE handshake. Forward it to
   * Privy's authenticated write endpoints (e.g. linking an email), which
   * authorize via these cookies rather than the bearer token alone.
   */
  cookie?: string;
}

interface PrivyPostResult {
  ok: boolean;
  status: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  json: any;
  /** Raw `Set-Cookie` values Privy returned (its session cookies). */
  setCookies: string[];
}

interface PrivyAuthPostOptions {
  /** Privy app id, sent as the `privy-app-id` header. */
  appId: string;
  /** Origin the request is scoped to (an allowed origin on the app). */
  origin: string;
  /** Privy auth API base. */
  authBase: string;
  /**
   * When set, sent as `Authorization: Bearer <accessToken>` — required for
   * calls that act on the authenticated user (e.g. linking an email).
   */
  accessToken?: string;
  /**
   * When set, sent as the `Cookie` header. Privy's authenticated write
   * endpoints (e.g. `passwordless/link`) authorize via the session cookies set
   * by `siwe/authenticate`; a headless client must forward them itself (the
   * `Authorization` bearer alone is not accepted there).
   */
  cookie?: string;
}

/**
 * POST JSON to an `auth.privy.io` endpoint with the headers Privy's WAF
 * expects (a browser User-Agent, the app id, and the scoped origin), plus an
 * optional bearer token and session cookie. Mirrors the Privy browser SDK's
 * internal fetch, including the session cookies a browser sends automatically.
 */
async function privyAuthPost(
  path: string,
  body: unknown,
  opts: PrivyAuthPostOptions,
): Promise<PrivyPostResult> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
    "privy-app-id": opts.appId,
    origin: opts.origin,
    "User-Agent": BROWSER_USER_AGENT,
  };
  if (opts.accessToken) {
    headers.Authorization = `Bearer ${opts.accessToken}`;
  }
  if (opts.cookie) {
    headers.Cookie = opts.cookie;
  }
  const res = await fetch(`${opts.authBase}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => null);
  return {
    ok: res.ok,
    status: res.status,
    json,
    setCookies: readSetCookies(res),
  };
}

/** Read `Set-Cookie` values off a fetch Response, tolerating test mocks. */
function readSetCookies(res: Response): string[] {
  const headers = res.headers as
    | (Headers & { getSetCookie?: () => string[] })
    | undefined;
  if (!headers) return [];
  if (typeof headers.getSetCookie === "function") return headers.getSetCookie();
  const single = headers.get?.("set-cookie");
  return single ? [single] : [];
}

/**
 * Fold `Set-Cookie` values into a `Cookie` header string (`name=value; ...`),
 * starting from any existing jar. Only each cookie's `name=value` is kept;
 * attributes (`Path`, `HttpOnly`, …) are dropped, as a client must.
 */
function mergeCookies(
  existing: string | undefined,
  setCookies: string[],
): string | undefined {
  const jar = new Map<string, string>();
  for (const pair of existing?.split("; ") ?? []) {
    const eq = pair.indexOf("=");
    if (eq > 0) jar.set(pair.slice(0, eq), pair.slice(eq + 1));
  }
  for (const sc of setCookies) {
    const nameValue = sc.split(";", 1)[0];
    const eq = nameValue.indexOf("=");
    if (eq > 0) {
      jar.set(nameValue.slice(0, eq).trim(), nameValue.slice(eq + 1).trim());
    }
  }
  if (jar.size === 0) return existing;
  return Array.from(jar, ([k, v]) => `${k}=${v}`).join("; ");
}

/** Append Privy's response body (its error message) to a failure message. */
function privyErrorDetail(json: unknown): string {
  if (json && typeof json === "object") {
    const o = json as Record<string, unknown>;
    const msg = o.error ?? o.message ?? o.code;
    if (typeof msg === "string" && msg) return `: ${msg}`;
    const serialized = JSON.stringify(json);
    if (serialized && serialized !== "{}") return `: ${serialized}`;
  }
  return "";
}

/**
 * Headlessly create (or re-authenticate) a Privy user from an EOA via
 * Sign-In-With-Ethereum, returning a Privy access token.
 *
 * This is the exact SIWE handshake the Zora web app performs in the browser,
 * run from a script instead: generate/supply an EOA, `siwe/init` to get a
 * nonce, sign the standard SIWE message, then `siwe/authenticate`. No Privy
 * dashboard, email, or OTP is required.
 *
 * Note: the target Privy app must allow `origin` and have CAPTCHA disabled for
 * this headless flow to succeed.
 */
export async function createPrivyAccount(
  opts: CreatePrivyAccountOptions,
): Promise<PrivyAccount> {
  const {
    privateKey,
    appId = ZORA_PRIVY_APP_ID,
    origin = DEFAULT_SIWE_ORIGIN,
    chainId = DEFAULT_SIWE_CHAIN_ID,
    walletClientType = "metamask",
    connectorType = "injected",
    authBase = PRIVY_AUTH_BASE,
  } = opts;

  const account = privateKeyToAccount(privateKey);
  const domain = new URL(origin).host;
  // Accumulate Privy's session cookies across the handshake so authenticated
  // write endpoints (e.g. passwordless/link) can be called afterward.
  let cookie: string | undefined;
  const post = (path: string, body: unknown) =>
    privyAuthPost(path, body, { appId, origin, authBase, cookie });

  const init = await post("/api/v1/siwe/init", { address: account.address });
  if (!init.ok || !init.json?.nonce) {
    throw new Error(
      `Privy siwe/init failed (HTTP ${init.status})${privyErrorDetail(init.json)}.`,
    );
  }
  cookie = mergeCookies(cookie, init.setCookies);

  const message = createSiweMessage({
    address: account.address,
    chainId,
    domain,
    uri: origin,
    version: "1",
    nonce: init.json.nonce,
    issuedAt: new Date(),
    statement:
      "By signing, you are proving you own this wallet and logging in. " +
      "This does not initiate a transaction or cost any fees.",
    resources: ["https://privy.io"],
  });
  const signature = await account.signMessage({ message });

  const auth = await post("/api/v1/siwe/authenticate", {
    message,
    signature,
    chainId: `eip155:${chainId}`,
    walletClientType,
    connectorType,
    mode: "login-or-sign-up",
  });
  if (!auth.ok || !auth.json?.token || !auth.json?.user?.id) {
    throw new Error(
      `Privy siwe/authenticate failed (HTTP ${auth.status})${privyErrorDetail(auth.json)}.`,
    );
  }
  cookie = mergeCookies(cookie, auth.setCookies);

  return {
    address: account.address,
    did: auth.json.user.id,
    accessToken: auth.json.token,
    accessTokenExpiresAt: accessTokenExpiry(auth.json.token),
    refreshToken: parseSetCookie(auth.setCookies, "privy-refresh-token"),
    identityToken: auth.json.identity_token,
    isNewUser: Boolean(auth.json.is_new_user),
    linkedAccounts: (auth.json.user.linked_accounts ??
      []) as PrivyLinkedAccount[],
    cookie,
  };
}

export interface RefreshPrivySessionOptions {
  /** The `privy-refresh-token` value captured from a prior authenticate/refresh. */
  refreshToken: string;
  /** Privy app id. Defaults to {@link ZORA_PRIVY_APP_ID}. */
  appId?: string;
  /** Origin the session is scoped to. Defaults to {@link DEFAULT_SIWE_ORIGIN}. */
  origin?: string;
  /** Privy auth API base. Override only for testing. */
  authBase?: string;
}

export interface PrivyRefreshResult {
  /** A fresh short-lived access token (JWT). */
  accessToken: string;
  /** Epoch ms at which {@link accessToken} expires, from its JWT `exp` claim. */
  accessTokenExpiresAt: number;
  /**
   * The rotated refresh token. Privy rotates the refresh token on every exchange,
   * so callers must persist this and discard the one they sent. Falls back to the
   * sent token if Privy returns neither a body field nor a Set-Cookie.
   */
  refreshToken: string;
  /** Privy identity token, when returned. */
  identityToken?: string;
  /** The Privy user DID, when the response includes the user object. */
  did?: string;
  /**
   * The user's linked accounts when the sessions endpoint returns the user object,
   * or `undefined` when it does not. Callers that need the *current* linked accounts
   * (e.g. embedded-wallet polling) must re-authenticate when this is `undefined`.
   */
  linkedAccounts?: PrivyLinkedAccount[];
}

/** Thrown when a refresh-token exchange at `/api/v1/sessions` is rejected (e.g. 401). */
export class PrivySessionExpiredError extends Error {
  constructor(public readonly status: number) {
    super(`Privy session refresh rejected (HTTP ${status}).`);
    this.name = "PrivySessionExpiredError";
  }
}

/**
 * Exchange a Privy refresh token for a fresh access token via `POST
 * /api/v1/sessions`, without re-running the SIWE handshake.
 *
 * `siwe/authenticate` is rate-limited (~60 calls/week per app), so long-lived or
 * frequently-invoked agents must refresh rather than re-sign in each time their
 * ~1h access token expires. The refresh token is sent both in the JSON body and
 * as a `privy-refresh-token` cookie, mirroring the browser SDK so Privy's WAF
 * accepts the call from a non-browser context.
 *
 * Throws {@link PrivySessionExpiredError} when the token is rejected, so callers
 * can fall back to a full {@link createPrivyAccount}.
 */
export async function refreshPrivySession(
  opts: RefreshPrivySessionOptions,
): Promise<PrivyRefreshResult> {
  const {
    refreshToken,
    appId = ZORA_PRIVY_APP_ID,
    origin = DEFAULT_SIWE_ORIGIN,
    authBase = PRIVY_AUTH_BASE,
  } = opts;

  // Send the refresh token both in the body and as the `privy-refresh-token`
  // cookie, mirroring the browser SDK so Privy's WAF accepts the headless call.
  const res = await privyAuthPost(
    "/api/v1/sessions",
    { refresh_token: refreshToken },
    { appId, origin, authBase, cookie: `privy-refresh-token=${refreshToken}` },
  );
  if (!res.ok) {
    throw new PrivySessionExpiredError(res.status);
  }
  if (!res.json?.token) {
    // A 2xx with no token is a malformed/unexpected response, not a rejected
    // refresh token — surface it distinctly so a genuine expiry isn't masked by
    // a misleading "rejected (HTTP 200)".
    throw new Error(
      `Privy session refresh returned no token (HTTP ${res.status}).`,
    );
  }

  const json = res.json;
  const linkedAccounts = Array.isArray(json.user?.linked_accounts)
    ? (json.user.linked_accounts as PrivyLinkedAccount[])
    : undefined;

  return {
    accessToken: json.token,
    accessTokenExpiresAt: accessTokenExpiry(json.token),
    // Privy rotates the refresh token via the `privy-refresh-token` Set-Cookie.
    // The JSON `refresh_token` field is now the literal sentinel "deprecated"
    // (Privy stopped returning the real token in the body), so it must never be
    // used as a token — sending it back yields HTTP 400 "Invalid auth token".
    // Prefer the rotated cookie; only fall back to a *real* body token, then to
    // the token we sent.
    refreshToken:
      parseSetCookie(res.setCookies, "privy-refresh-token") ??
      (typeof json.refresh_token === "string" &&
      json.refresh_token !== "deprecated"
        ? json.refresh_token
        : undefined) ??
      refreshToken,
    identityToken:
      typeof json.identity_token === "string" ? json.identity_token : undefined,
    did: typeof json.user?.id === "string" ? json.user.id : undefined,
    linkedAccounts,
  };
}

/** Default access-token lifetime used when a token's `exp` can't be read (~1h). */
const DEFAULT_ACCESS_TOKEN_TTL_MS = 60 * 60 * 1000;

/**
 * The epoch-ms expiry of a Privy access token, from its JWT `exp` claim. Falls back
 * to ~1h from now when the token can't be decoded, so callers always get a usable
 * (if conservative) expiry.
 */
export function accessTokenExpiry(jwt: string): number {
  const exp = decodeJwtExp(jwt);
  return exp !== undefined
    ? exp * 1000
    : Date.now() + DEFAULT_ACCESS_TOKEN_TTL_MS;
}

/** The `exp` claim (seconds since epoch) of a JWT, or undefined if unreadable. */
function decodeJwtExp(jwt: string): number | undefined {
  const segments = jwt.split(".");
  if (segments.length < 2) return undefined;
  try {
    const payload = JSON.parse(
      Buffer.from(segments[1], "base64url").toString("utf-8"),
    );
    return typeof payload?.exp === "number" ? payload.exp : undefined;
  } catch {
    return undefined;
  }
}

/**
 * The value of the named cookie from a list of `Set-Cookie` header values, or
 * undefined if absent or explicitly cleared (empty value).
 */
export function parseSetCookie(
  setCookies: string[],
  name: string,
): string | undefined {
  const prefix = `${name}=`;
  for (const cookie of setCookies) {
    if (cookie.startsWith(prefix)) {
      const value = cookie.slice(prefix.length).split(";", 1)[0];
      return value || undefined;
    }
  }
  return undefined;
}

/**
 * The agent's embedded (Privy-managed) wallet address from its linked accounts,
 * if one has been provisioned. The embedded wallet appears after the agent's
 * profile is created (`createAgentProfile`), so this may be undefined immediately
 * after the first sign-in.
 */
export function findEmbeddedWallet(
  linkedAccounts: PrivyLinkedAccount[],
): `0x${string}` | undefined {
  const embedded = linkedAccounts.find(
    (a) => a.type === "wallet" && a.wallet_client_type === "privy",
  );
  const address = embedded?.address;
  // Validate the prefix at runtime: the linked-account address is typed as a
  // plain string, so a non-0x value would otherwise slip past the cast and only
  // fail later inside viem's on-chain calls, where the error is far less clear.
  if (!address?.startsWith("0x")) return undefined;
  return address as `0x${string}`;
}

export interface SendEmailCodeOptions {
  /** Privy session access token from {@link createPrivyAccount}. */
  accessToken: string;
  /** Email address to send the one-time code to. */
  email: string;
  /** Privy app id. Defaults to {@link ZORA_PRIVY_APP_ID}. */
  appId?: string;
  /** Origin the request is scoped to. Defaults to {@link DEFAULT_SIWE_ORIGIN}. */
  origin?: string;
  /** Privy auth API base. Override only for testing. */
  authBase?: string;
  /** Session cookie from {@link createPrivyAccount} (Privy's authenticated session). */
  cookie?: string;
}

/**
 * Send a one-time code to {@link SendEmailCodeOptions.email} via Privy's
 * passwordless flow, so it can then be attached to the authenticated user with
 * {@link linkEmailWithCode}. CAPTCHA is disabled on the Zora app, so no captcha
 * `token` is sent.
 *
 * @throws if Privy rejects the request (non-2xx).
 */
export async function sendEmailCode(opts: SendEmailCodeOptions): Promise<void> {
  const {
    accessToken,
    email,
    appId = ZORA_PRIVY_APP_ID,
    origin = DEFAULT_SIWE_ORIGIN,
    authBase = PRIVY_AUTH_BASE,
    cookie,
  } = opts;

  const res = await privyAuthPost(
    "/api/v1/passwordless/init",
    { email },
    { appId, origin, authBase, accessToken, cookie },
  );
  if (!res.ok) {
    throw new Error(
      `Privy passwordless/init failed (HTTP ${res.status})${privyErrorDetail(res.json)}.`,
    );
  }
}

export interface LinkEmailWithCodeOptions {
  /** Privy session access token for the user the email is linked to. */
  accessToken: string;
  /** Email address being linked (the one the code was sent to). */
  email: string;
  /** The one-time code from the email. */
  code: string;
  /** Privy app id. Defaults to {@link ZORA_PRIVY_APP_ID}. */
  appId?: string;
  /** Origin the request is scoped to. Defaults to {@link DEFAULT_SIWE_ORIGIN}. */
  origin?: string;
  /** Privy auth API base. Override only for testing. */
  authBase?: string;
  /** Session cookie from {@link createPrivyAccount} (Privy's authenticated session). */
  cookie?: string;
}

export interface LinkEmailResult {
  /** The email now linked to the user (as recorded by Privy). */
  email: string;
  /** The user's linked accounts after the email was attached. */
  linkedAccounts: PrivyLinkedAccount[];
}

/**
 * Verify {@link LinkEmailWithCodeOptions.code} and attach the email to the
 * Privy user identified by the access token — linking it to the existing
 * account rather than logging in as a new user.
 *
 * @throws if the code is wrong/expired, the email belongs to another user, or
 *   Privy otherwise rejects the request (non-2xx).
 */
export async function linkEmailWithCode(
  opts: LinkEmailWithCodeOptions,
): Promise<LinkEmailResult> {
  const {
    accessToken,
    email,
    code,
    appId = ZORA_PRIVY_APP_ID,
    origin = DEFAULT_SIWE_ORIGIN,
    authBase = PRIVY_AUTH_BASE,
    cookie,
  } = opts;

  const res = await privyAuthPost(
    "/api/v1/passwordless/link",
    { email, code },
    { appId, origin, authBase, accessToken, cookie },
  );
  if (!res.ok || !res.json?.linked_accounts) {
    throw new Error(
      `Privy passwordless/link failed (HTTP ${res.status})${privyErrorDetail(res.json)}.`,
    );
  }

  const linkedAccounts = res.json.linked_accounts as PrivyLinkedAccount[];
  const linkedEmail =
    linkedAccounts.find((a) => a.type === "email" && a.address)?.address ??
    email;

  return { email: linkedEmail, linkedAccounts };
}

/**
 * Whether `email` is already linked to these accounts (case-insensitive),
 * letting the caller skip re-sending a code for an email already on the account.
 */
export function hasLinkedEmail(
  linkedAccounts: PrivyLinkedAccount[],
  email: string,
): boolean {
  const target = email.trim().toLowerCase();
  return linkedAccounts.some(
    (a) => a.type === "email" && a.address?.toLowerCase() === target,
  );
}
