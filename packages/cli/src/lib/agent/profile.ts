import { graphqlRequest } from "./zora-client.js";

export interface AgentProfile {
  /** The randomly-assigned Zora handle (e.g. `keen_cedar_9807`). */
  username: string;
  /** The default avatar URI, if one was set. */
  avatarUri?: string;
}

const CREATE_PROFILE_MUTATION =
  "mutation CreateAgentProfile { createAgentProfile { username avatar { originalUri } } }";

export interface CreateAgentProfileOptions {
  /** Retry attempts (the embedded-wallet provisioning is eventually-consistent). */
  attempts?: number;
  sleep?: (ms: number) => Promise<void>;
}

/**
 * Create the agent's Zora profile (or return the existing one — the mutation is
 * idempotent per Privy user). It takes no arguments: the Privy session token is
 * the sole credential, and it provisions the agent's embedded wallet server-side.
 *
 * That embedded-wallet provisioning is eventually-consistent, so the first call
 * on a brand-new user can fail with "unable to create embedded wallet" even
 * though the wallet is created moments later — we retry until it succeeds.
 */
export async function createAgentProfile(
  token: string,
  opts: CreateAgentProfileOptions = {},
): Promise<AgentProfile> {
  const attempts = opts.attempts ?? 5;
  const sleep =
    opts.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));

  let lastError = "no profile returned";
  for (let attempt = 0; attempt < attempts; attempt++) {
    const { data, errors, status } = await graphqlRequest(
      token,
      CREATE_PROFILE_MUTATION,
      "CreateAgentProfile",
    );
    const profile = data?.createAgentProfile;
    if (profile?.username) {
      return {
        username: profile.username,
        avatarUri: profile.avatar?.originalUri,
      };
    }
    lastError = errors?.[0]?.message ?? `HTTP ${status}`;
    // Only the embedded-wallet provisioning race is transient and worth a retry.
    // Anything else (expired token, 401/403, an unexpected server error) won't
    // resolve by waiting, so fail fast instead of stalling 4s per attempt.
    if (!/unable to create embedded wallet/i.test(lastError)) break;
    if (attempt < attempts - 1) await sleep(4000);
  }
  throw new Error(`createAgentProfile failed: ${lastError}`);
}
