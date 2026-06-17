import { graphqlRequest } from "./agent/zora-client.js";

/**
 * Viewer-context follow status the universal API reports for a profile, relative
 * to the signed-in user. After a successful `follow` the target is `FOLLOWING`
 * (or `MUTUAL_FOLLOWING` when they already follow back); after `unfollow` it is
 * `NOT_FOLLOWING` (or `FOLLOWED` when they still follow the user). `SELF` means
 * the identifier resolved to the user's own profile.
 */
export type FollowingStatus =
  | "FOLLOWED"
  | "FOLLOWING"
  | "MUTUAL_FOLLOWING"
  | "NOT_FOLLOWING"
  | "SELF"
  | "UNKNOWN";

export interface FollowResult {
  /** The target's handle — its username, or a truncated address if it has no profile. */
  handle: string;
  /** The target's profile id — its username, or full wallet address if it has no profile. */
  profileId: string;
  /** The viewer-context follow status after the mutation. */
  followingStatus: FollowingStatus;
}

const FOLLOW_MUTATION =
  "mutation CliFollow($followeeId: String!) { follow(followeeId: $followeeId) { handle profileId vcFollowingStatus } }";

const UNFOLLOW_MUTATION =
  "mutation CliUnfollow($followeeId: String!) { unfollow(followeeId: $followeeId) { handle profileId vcFollowingStatus } }";

/**
 * Run a follow/unfollow mutation against the Zora universal GraphQL API,
 * authenticated by the caller's Privy access token (the viewer context the
 * mutation needs). Both mutations return the target profile, so the parsing is
 * shared — only the query, operation name, and response field differ.
 */
async function mutateFollow(
  token: string,
  followeeId: string,
  mutation: string,
  operationName: string,
  field: "follow" | "unfollow",
): Promise<FollowResult> {
  const { data, errors, status } = await graphqlRequest(
    token,
    mutation,
    operationName,
    { followeeId },
  );
  const profile = data?.[field];
  if (profile?.profileId) {
    return {
      // The API returns the full address as both fields when the target has no
      // profile; fall back to profileId so handle is never empty.
      handle: profile.handle ?? profile.profileId,
      profileId: profile.profileId,
      followingStatus: (profile.vcFollowingStatus ??
        "UNKNOWN") as FollowingStatus,
    };
  }
  const lastError = errors?.[0]?.message ?? `HTTP ${status}`;
  throw new Error(`${field} failed: ${lastError}`);
}

/**
 * Follow a Zora user. `followeeId` accepts any identifier the API resolves a
 * profile from: a username (handle), a wallet address, or an account id.
 */
export function followProfile(
  token: string,
  followeeId: string,
): Promise<FollowResult> {
  return mutateFollow(
    token,
    followeeId,
    FOLLOW_MUTATION,
    "CliFollow",
    "follow",
  );
}

/**
 * Unfollow a Zora user. Accepts the same identifier forms as {@link followProfile}.
 */
export function unfollowProfile(
  token: string,
  followeeId: string,
): Promise<FollowResult> {
  return mutateFollow(
    token,
    followeeId,
    UNFOLLOW_MUTATION,
    "CliUnfollow",
    "unfollow",
  );
}
