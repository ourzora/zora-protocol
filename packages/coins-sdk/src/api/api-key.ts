let apiKey: string | undefined;
let privyJwt: string | undefined;

export function setApiKey(key: string | undefined) {
  apiKey = key;
}

export function getApiKey() {
  return apiKey;
}

/**
 * Set the Privy access token used to authenticate Privy-gated Zora mutations
 * (profile updates, follow/block, DMs, etc.). For agent accounts the token
 * comes from `agentSiweLogin`; for human accounts from Privy's client SDKs.
 * Pass `undefined` to clear.
 */
export function setPrivyJwt(jwt: string | undefined) {
  privyJwt = jwt;
}

export function getPrivyJwt() {
  return privyJwt;
}

/**
 * Returns the headers to attach to outbound SDK requests, including the
 * Zora API key and (when set) the Privy JWT as `Authorization: Bearer`.
 * Both are optional; returns `{}` when neither is configured.
 */
export function getAuthMeta() {
  const headers: Record<string, string> = {};
  if (apiKey) headers["api-key"] = apiKey;
  if (privyJwt) headers["Authorization"] = `Bearer ${privyJwt}`;
  return Object.keys(headers).length === 0 ? {} : { headers };
}

/**
 * @deprecated Use `getAuthMeta` instead. Kept as an alias so existing callers
 * in `api/queries.ts` continue to compile while migration happens incrementally.
 * Behaviour is identical to `getAuthMeta` — both inject the Privy JWT header
 * when one is set via `setPrivyJwt`.
 */
export const getApiKeyMeta = getAuthMeta;
