/* eslint-disable @typescript-eslint/no-explicit-any */
import type { Address, Hex } from "viem";

/**
 * The subset of a viem PublicClient the agent flow uses. Kept structural so a
 * client created in another module doesn't trip viem's duplicate-type checks,
 * and so tests can pass a lightweight fake.
 */
export interface ChainClient {
  readContract(args: any): Promise<any>;
  getCode(args: { address: Address }): Promise<Hex | undefined>;
  call(args: { to: Address; data: Hex }): Promise<unknown>;
  /**
   * Fetch a mined transaction's receipt. Used to resolve a deployed coin's
   * address from the transaction's authoritative on-chain logs when the inline
   * `submitUserOperation` logs are absent. Optional so lightweight test fakes
   * (and any caller that doesn't need it) can omit it.
   */
  getTransactionReceipt?(args: { hash: Hex }): Promise<{ logs?: unknown[] }>;
}

/** Zora BFF (tRPC) base — takes the RAW Privy token (no "Bearer"). */
export const ZORA_TRPC_BASE = "https://zora.co/api/trpc";
/** Zora universal GraphQL — takes `Authorization: Bearer <token>`. */
export const ZORA_GRAPHQL = "https://api.zora.co/universal/graphql";
/** Zora IPFS uploader — takes `Authorization: Bearer <token>`, multipart body. */
export const ZORA_IPFS_UPLOAD =
  "https://ipfs-uploader.zora.co/api/v0/add?cid-version=1";
export const ZORA_ORIGIN = "https://zora.co";

/** ZoraAccountManager (Coinbase smart-wallet factory wrapper) on Base. */
export const ZORA_ACCOUNT_MANAGER: Address =
  "0x0Ba958A449701907302e28F5955fa9d16dDC45c3";
/** Base mainnet. */
export const BASE_CHAIN_ID = 8453;
/** GraphQL `EChainName` enum value for Base mainnet. */
export const BASE_CHAIN_NAME = "BaseMainnet";
/** Deterministic-address nonce the Zora flow uses when deploying the smart wallet. */
export const SMART_WALLET_NONCE = 1n;
/** Owner index of the external EOA (index 0 is the browser-only embedded wallet). */
export const EXTERNAL_OWNER_INDEX = 1;

// Cloudflare's WAF 403s non-browser User-Agents on the Zora + Privy + Base RPC endpoints.
export const BROWSER_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";

/** A superjson-encoded tRPC input: `{ json, meta? }`. */
export interface SuperjsonInput {
  json: unknown;
  meta?: { values: Record<string, string[]> };
}

export interface TrpcResult {
  status: number;
  /** The unwrapped `result.data.json`, when present. */
  data: any;
  /** An error message, when the call failed. */
  error?: string;
  text: string;
}

/** POST a non-batch superjson mutation to the Zora tRPC BFF (raw token). */
export async function trpcRequest(
  token: string,
  proc: string,
  input: SuperjsonInput,
): Promise<TrpcResult> {
  const res = await fetch(`${ZORA_TRPC_BASE}/${proc}`, {
    method: "POST",
    headers: {
      authorization: token,
      "content-type": "application/json",
      origin: ZORA_ORIGIN,
      "user-agent": BROWSER_USER_AGENT,
    },
    body: JSON.stringify(input),
  });
  const text = await res.text();
  let parsed: any;
  try {
    parsed = JSON.parse(text);
  } catch {
    return {
      status: res.status,
      data: undefined,
      error: `non-JSON response (HTTP ${res.status})`,
      text,
    };
  }
  const data = parsed?.result?.data?.json;
  const error =
    data === undefined
      ? parsed?.error?.json?.message ||
        parsed?.error?.message ||
        `HTTP ${res.status}`
      : undefined;
  return { status: res.status, data, error, text };
}

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

/**
 * Upload a file to Zora's IPFS service and return its `ipfs://<cid>` URI.
 * Auth is `Bearer` here (unlike the raw-token tRPC). The response is
 * newline-delimited JSON (`{ name, cid, size }` per line).
 */
export async function ipfsUpload(
  token: string,
  filename: string,
  bytes: Uint8Array,
  mimeType: string,
): Promise<string> {
  const form = new FormData();
  form.append(
    filename,
    new Blob([bytes as BlobPart], { type: mimeType }),
    filename,
  );
  const res = await fetch(ZORA_IPFS_UPLOAD, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "user-agent": BROWSER_USER_AGENT,
    },
    body: form,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(
      `IPFS upload failed (HTTP ${res.status}): ${text.slice(0, 200)}`,
    );
  }
  const lines = text
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line) as { name: string; cid: string });
  const match =
    lines.find((l) => l.name === filename) ?? lines[lines.length - 1];
  if (!match?.cid) throw new Error("IPFS upload returned no CID");
  return `ipfs://${match.cid}`;
}
