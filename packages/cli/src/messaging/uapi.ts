import { type Address, getAddress, isAddress } from "viem";
import type { MessagingProfile } from "./types.js";
import { readProfileCache, writeProfileCache } from "../lib/profile-cache.js";

/**
 * The non-XMTP calls the DM feature needs: resolving a counterpart address to its
 * Zora profile (handle/avatar) and the new-conversation gate (rate limit + token
 * gate + mutual-follow bypass). The gate hits the universal GraphQL endpoint and
 * requires a logged-in viewer context (the Privy JWT); profile resolution hits the
 * public profile endpoint and needs no auth.
 */

const UAPI_BASE = (
  process.env.ZORA_API_TARGET ?? "https://api.zora.co"
).replace(/\/$/, "");

const UAPI_GRAPHQL = `${UAPI_BASE}/universal/graphql`;

/**
 * Per-request timeout so a slow/unreachable UAPI fails fast instead of hanging
 * every `zora dm` subcommand indefinitely.
 */
const REQUEST_TIMEOUT_MS = 15_000;

interface GraphQLResponse<T> {
  data?: T;
  errors?: { message: string }[];
}

/** Minimal GraphQL POST with optional bearer auth. Throws on transport/GraphQL errors. */
export const graphqlRequest = async <T>(
  query: string,
  variables: Record<string, unknown>,
  token?: string,
): Promise<T> => {
  const response = await fetch(UAPI_GRAPHQL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ query, variables }),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });

  if (!response.ok) {
    throw new Error(`UAPI request failed: HTTP ${response.status}`);
  }

  const body = (await response.json()) as GraphQLResponse<T>;
  if (body.errors?.length) {
    throw new Error(
      `UAPI error: ${body.errors.map((e) => e.message).join("; ")}`,
    );
  }
  if (!body.data) {
    throw new Error("UAPI returned no data");
  }
  return body.data;
};

/**
 * Public Zora profile lookup (no auth). Resolves an address to its handle/avatar
 * — the same data the SDK's `getProfile` returns, e.g.
 * `https://api-sdk.zora.engineering/profile?identifier=0x...`.
 */
const PROFILE_API = (
  process.env.ZORA_PROFILE_API ?? "https://api-sdk.zora.engineering"
).replace(/\/$/, "");

interface ProfileApiResponse {
  profile?: {
    handle?: string | null;
    username?: string | null;
    displayName?: string | null;
    platformBlocked?: boolean | null;
    avatar?: { previewImage?: { small?: string | null } | null } | null;
    linkedWallets?: {
      edges?: Array<{
        node?: { walletType?: string | null; walletAddress?: string | null };
      }> | null;
    } | null;
  } | null;
}

export type HandleResolution =
  | { ok: true; address: Address }
  /** No Zora account with that handle. */
  | { ok: false; reason: "not-found" }
  /** Account exists but has no DM-capable smart wallet. */
  | { ok: false; reason: "no-inbox" }
  /** Couldn't reach the API (network/transient). */
  | { ok: false; reason: "error" };

/**
 * Resolves a Zora handle (e.g. `wbnns`, with or without a leading `@`) to the
 * address its DM inbox is keyed on — the user's Coinbase Smart Wallet.
 * Distinguishes a missing account, an account with no DM inbox, and a transient
 * error so callers can give a specific message.
 */
export const resolveHandleToAddress = async (
  handle: string,
): Promise<HandleResolution> => {
  const identifier = handle.replace(/^@/, "").trim();
  if (!identifier) return { ok: false, reason: "not-found" };

  let profile: ProfileApiResponse["profile"];
  try {
    const response = await fetch(
      `${PROFILE_API}/profile?identifier=${encodeURIComponent(identifier)}`,
      { signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS) },
    );
    if (response.status === 404) return { ok: false, reason: "not-found" };
    if (!response.ok) return { ok: false, reason: "error" };
    ({ profile } = (await response.json()) as ProfileApiResponse);
  } catch {
    return { ok: false, reason: "error" };
  }

  if (!profile) return { ok: false, reason: "not-found" };
  const wallet = profile.linkedWallets?.edges?.find(
    (e) => e.node?.walletType === "SMART_WALLET",
  )?.node?.walletAddress;
  if (!wallet || !isAddress(wallet)) return { ok: false, reason: "no-inbox" };
  return { ok: true, address: getAddress(wallet) };
};

/** Refresh a cached profile after this long, in case the handle changed. */
const PROFILE_TTL_MS = 24 * 60 * 60 * 1000;

/**
 * Max profile lookups in flight at once. Bounds the burst when many uncached
 * senders appear together (e.g. an agent with 100 new requests) so we don't fire
 * 100 simultaneous requests at the API. Cache hits don't count toward this.
 */
const PROFILE_FETCH_CONCURRENCY = 8;

const fetchProfile = async (address: Address): Promise<MessagingProfile> => {
  try {
    const response = await fetch(
      `${PROFILE_API}/profile?identifier=${address}`,
      {
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      },
    );
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const { profile } = (await response.json()) as ProfileApiResponse;
    const handle = profile?.handle ?? profile?.username ?? null;
    return {
      address,
      handle,
      displayName: profile?.displayName ?? handle,
      avatarUrl: profile?.avatar?.previewImage?.small ?? null,
      platformBlocked: profile?.platformBlocked ?? false,
    };
  } catch {
    return {
      address,
      handle: null,
      displayName: null,
      avatarUrl: null,
      platformBlocked: false,
    };
  }
};

/**
 * Resolves addresses to Zora profiles for human-readable output, backed by a
 * local cache so a growing or high-volume inbox doesn't re-look-up known people
 * on every command — only addresses missing or older than {@link PROFILE_TTL_MS}
 * are fetched. Best-effort: lookups that fail or have no profile resolve to a
 * `null`-field entry rather than throwing, so a single bad address never breaks
 * `dm list`. The second argument is ignored — this hits the public profile
 * endpoint, no token needed.
 */
export const resolveProfiles = async (
  addresses: Address[],
  _token?: string,
  onProgress?: (done: number, total: number) => void,
): Promise<Map<Address, MessagingProfile>> => {
  const map = new Map<Address, MessagingProfile>();
  const cache = readProfileCache();
  const now = Date.now();
  const stale: Address[] = [];

  for (const address of addresses) {
    const cached = cache[address.toLowerCase()];
    if (cached && now - cached.fetchedAt < PROFILE_TTL_MS) {
      map.set(address, {
        address,
        handle: cached.handle,
        displayName: cached.displayName,
        avatarUrl: cached.avatarUrl,
        platformBlocked: cached.platformBlocked ?? false,
      });
    } else {
      stale.push(address);
    }
  }

  if (stale.length > 0) {
    // Fetch in bounded-concurrency batches rather than all at once, reporting
    // progress over the uncached lookups (cache hits above are instant).
    let done = 0;
    onProgress?.(0, stale.length);
    for (let i = 0; i < stale.length; i += PROFILE_FETCH_CONCURRENCY) {
      const batch = stale.slice(i, i + PROFILE_FETCH_CONCURRENCY);
      const fetched = await Promise.all(
        batch.map(async (address) => {
          const profile = await fetchProfile(address);
          done += 1;
          onProgress?.(done, stale.length);
          return profile;
        }),
      );
      for (const profile of fetched) {
        map.set(profile.address, profile);
        cache[profile.address.toLowerCase()] = {
          handle: profile.handle,
          displayName: profile.displayName,
          avatarUrl: profile.avatarUrl,
          platformBlocked: profile.platformBlocked,
          fetchedAt: now,
        };
      }
    }
    writeProfileCache(cache);
  }

  return map;
};

const GATE_MUTATION = `
  mutation CliCheckNewDmConversationAllowed($recipientAddress: TStrAddress!) {
    checkNewDmConversationAllowed(recipientAddress: $recipientAddress) {
      allowed
      retryAfterSeconds
    }
  }
`;

export interface NewConversationGateResult {
  allowed: boolean;
  retryAfterSeconds: number;
}

/**
 * Calls `checkNewDmConversationAllowed` as the logged-in viewer. Requires the
 * Privy JWT; without it the backend can't establish a viewer context.
 */
export const checkNewDmConversationAllowed = async (
  recipientAddress: Address,
  token: string,
): Promise<NewConversationGateResult> => {
  const data = await graphqlRequest<{
    checkNewDmConversationAllowed: NewConversationGateResult;
  }>(GATE_MUTATION, { recipientAddress }, token);
  return data.checkNewDmConversationAllowed;
};

const REGISTER_INSTALLATION_MUTATION = `
  mutation CliRegisterXmtpInstallation(
    $installationId: String!
    $devicePlatform: EXmtpDevicePlatform!
  ) {
    registerXmtpInstallation(
      installationId: $installationId
      devicePlatform: $devicePlatform
    ) {
      id
    }
  }
`;

/**
 * Registers this CLI's XMTP installation with the Zora backend so it appears in
 * the user's installation list (as the `CLI` device platform) and is tracked
 * against the per-inbox installation cap. Requires the Privy JWT. The `CLI`
 * device-platform enum value is added in ourzora/zora#3305.
 */
export const registerXmtpInstallation = async (
  installationId: string,
  token: string,
): Promise<void> => {
  await graphqlRequest(
    REGISTER_INSTALLATION_MUTATION,
    { installationId, devicePlatform: "CLI" },
    token,
  );
};
