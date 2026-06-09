/* eslint-disable @typescript-eslint/no-explicit-any */

/** Zora universal GraphQL — takes `Authorization: Bearer <token>`. */
export const ZORA_GRAPHQL = "https://api.zora.co/universal/graphql";
export const ZORA_ORIGIN = "https://zora.co";

// Cloudflare's WAF 403s non-browser User-Agents on the Zora + Privy endpoints.
export const BROWSER_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

export interface GraphqlResult {
  status: number;
  data: any;
  errors?: Array<{ message?: string }>;
  text: string;
}

/** POST a mutation to the Zora universal GraphQL (Bearer token, Relay shape). */
export async function graphqlRequest(
  token: string,
  query: string,
  operationName: string,
  variables?: Record<string, unknown>,
): Promise<GraphqlResult> {
  const res = await fetch(ZORA_GRAPHQL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
      // Mirrors the Accept header the Zora web app's Apollo client sends. The
      // universal API sits behind a WAF that fingerprints browser-like requests,
      // so this is kept byte-for-byte (verified end-to-end). It reads like a
      // malformed media-type, but plain "application/json" is untested here and
      // changing it risks the request being rejected.
      accept: "multipart/mixed; application/json",
      origin: ZORA_ORIGIN,
      "user-agent": BROWSER_USER_AGENT,
    },
    body: JSON.stringify({
      query,
      operationName,
      ...(variables ? { variables } : {}),
    }),
  });
  const text = await res.text();
  let parsed: any;
  try {
    parsed = JSON.parse(text);
  } catch {
    return {
      status: res.status,
      data: undefined,
      errors: [{ message: `non-JSON (HTTP ${res.status})` }],
      text,
    };
  }
  return {
    status: res.status,
    data: parsed?.data,
    errors: parsed?.errors,
    text,
  };
}
