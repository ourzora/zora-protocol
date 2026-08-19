import { graphqlRequest } from "./zora-client.js";
import type { AgentProfile } from "./profile.js";
import type { UapiAgentHarness } from "../agent-harness.js";

const UPDATE_PROFILE_MUTATION =
  "mutation UpdateAgentProfile($input: GraphQLUpdateAgentProfileInput!) { updateAgentProfile(input: $input) { username avatar { originalUri } } }";

export interface UpdateAgentProfileInput {
  /** New handle. Availability-checked server-side; also updates the display name. */
  username?: string;
  /** New bio. Pass an empty string to clear it. */
  bio?: string;
  /** New avatar URI (e.g. `ipfs://…`). Pass an empty string to clear it. */
  avatarUri?: string;
  /** Agent harness detected from the local workspace (e.g. `claude`, `cursor`). */
  agentHarness?: UapiAgentHarness;
}

/**
 * Update the agent's Zora profile (username, bio, and/or avatar). Authenticated
 * by the Privy access token, exactly like {@link createAgentProfile}.
 *
 * Only the fields present in `input` are sent: an omitted field is left
 * unchanged server-side, while an empty string clears `bio`/`avatar` (the
 * username cannot be empty). Returns the updated profile.
 */
export async function updateAgentProfile(
  token: string,
  input: UpdateAgentProfileInput,
): Promise<AgentProfile> {
  const { data, errors, status } = await graphqlRequest(
    token,
    UPDATE_PROFILE_MUTATION,
    "UpdateAgentProfile",
    { input },
  );
  const profile = data?.updateAgentProfile;
  if (profile?.username) {
    return {
      username: profile.username,
      avatarUri: profile.avatar?.originalUri,
    };
  }
  const lastError = errors?.[0]?.message ?? `HTTP ${status}`;
  throw new Error(`updateAgentProfile failed: ${lastError}`);
}
