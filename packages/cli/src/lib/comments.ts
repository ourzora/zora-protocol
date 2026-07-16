import { getCoinMergedComments } from "@zoralabs/coins-sdk";
import { graphqlRequest } from "./agent/zora-client.js";

/**
 * Off-chain comments live entirely in Zora's backend (Mongo + the universal
 * GraphQL API) rather than in the on-chain Comments contract. There is no
 * transaction, no spark payment, and — unlike the on-chain path — no
 * coin-holding requirement: any signed-in profile may comment, subject to the
 * backend's rate limit and moderation gates. Auth is the caller's Privy access
 * token (the logged-in viewer context the mutation requires).
 *
 * This mirrors the web/mobile `createOffChainComment` mutation, minus the
 * `comment-offchain` feature flag (the CLI treats off-chain comments as always
 * enabled).
 */

/** Backend cap on comment length (`MAX_COMMENT_LENGTH`). */
export const MAX_COMMENT_LENGTH = 280;

/** Coins (zora20 tokens) are commented on with tokenId "0". */
export const COIN_OFF_CHAIN_TOKEN_ID = "0";

/** The resolved off-chain comment, flattened from the returned Relay edge. */
export interface OffChainCommentResult {
  /** The backend id of the created comment (Relay-agnostic string id). */
  commentId: string;
  /** The stored comment text (post-trim, as the backend persisted it). */
  text: string;
  /** ISO timestamp the backend stamped the comment with. */
  commentedAt: string;
  /** The pagination cursor for the new edge. */
  cursor: string;
  /** The commenter's handle, when the profile resolved to one. */
  handle?: string;
  /** The commenter's profile id, when available. */
  profileId?: string;
}

export interface CreateOffChainCommentParams {
  /** `EChainName` enum value (e.g. "BaseMainnet"). */
  chainName: string;
  /** Coin contract address; lowercased to match backend storage. */
  contractAddress: string;
  /** Token id — "0" for a coin. */
  tokenId: string;
  /** Comment body. */
  text: string;
  /** Parent off-chain comment id, when replying to an off-chain comment. */
  replyToOffChainId?: string;
  /** Parent on-chain comment id, when replying to a legacy on-chain comment. */
  replyToOnChainId?: string;
}

const CREATE_OFF_CHAIN_COMMENT_MUTATION = `mutation CliCommentOffChain(
  $chainName: EChainName!
  $contractAddress: TStrAddress!
  $tokenId: GraphQLStrTokenId!
  $text: String!
  $replyToOffChainId: String
  $replyToOnChainId: String
) {
  createOffChainComment(
    chainName: $chainName
    contractAddress: $contractAddress
    tokenId: $tokenId
    text: $text
    replyToOffChainId: $replyToOffChainId
    replyToOnChainId: $replyToOnChainId
  ) {
    cursor
    node {
      id
      commentId
      text
      commentedAt
      replyToOffChainId
      replyToOnChainId
      sparkCount
      vcIsSparkedByViewer
      profile {
        ... on GraphQLAccountProfile {
          id
          profileId
          handle
        }
      }
    }
  }
}`;

/**
 * Post an off-chain comment to a coin via the Zora universal GraphQL API,
 * authenticated by the caller's Privy access token. Returns the created
 * comment's id, text, and edge cursor. Throws with the API's error message
 * (rate limit, restriction, missing viewer context, …) when the mutation fails.
 */
export async function createOffChainComment(
  token: string,
  params: CreateOffChainCommentParams,
): Promise<OffChainCommentResult> {
  const { data, errors, status } = await graphqlRequest(
    token,
    CREATE_OFF_CHAIN_COMMENT_MUTATION,
    "CliCommentOffChain",
    {
      chainName: params.chainName,
      contractAddress: params.contractAddress.toLowerCase(),
      tokenId: params.tokenId,
      text: params.text,
      // The backend rejects setting both reply targets, so only forward a value
      // when it's set (leaving the other null).
      replyToOffChainId: params.replyToOffChainId ?? null,
      replyToOnChainId: params.replyToOnChainId ?? null,
    },
  );

  const edge = data?.createOffChainComment;
  const node = edge?.node;
  if (node?.commentId) {
    const profile = node.profile;
    return {
      commentId: node.commentId,
      text: node.text ?? params.text,
      commentedAt: node.commentedAt,
      cursor: edge.cursor,
      handle: profile?.handle ?? undefined,
      profileId: profile?.profileId ?? undefined,
    };
  }

  const lastError = errors?.[0]?.message ?? `HTTP ${status}`;
  throw new Error(lastError);
}

// --- Reading comments (merged on-chain + off-chain) ---

/**
 * A comment flattened from the merged connection into a single display shape,
 * regardless of whether it's on-chain (`GraphQLComment` /
 * `GraphQLBackfilledComment`) or off-chain (`GraphQLOffChainComment`). The
 * union members use different field names (e.g. `comment`/`timestamp` vs
 * `text`/`commentedAt`), so this normalizes them; the backend already returns
 * the two sources merged and sorted newest-first under one cursor.
 */
export interface MergedComment {
  commentId: string;
  /** True for off-chain comments, false for on-chain ones. */
  offChain: boolean;
  text: string;
  /** Unix timestamp in seconds (off-chain ISO times are converted). */
  timestamp: number;
  /** The commenter's handle, when they have a Zora profile. */
  handle?: string;
  /** The commenter's wallet address (on-chain comments only). */
  authorAddress?: string;
  sparkCount: number;
  replyCount: number;
}

export interface MergedCommentsPage {
  comments: MergedComment[];
  /** Total comment count across all pages. */
  totalCount: number;
  /** Cursor for the next page, when more results exist. */
  nextCursor?: string;
}

/* eslint-disable @typescript-eslint/no-explicit-any */
/**
 * Flatten one merged-feed node into a {@link MergedComment}, branching on
 * source. The response carries `__typename` at runtime, but it is NOT part of
 * the endpoint's typed contract, so we treat it as a hint and fall back to
 * field shape when it's absent — off-chain nodes carry `commentedAt`/`text`,
 * on-chain nodes carry `timestamp`/`comment`. This avoids silently dropping
 * every comment (→ a false "No comments yet") if `__typename` ever goes missing.
 */
function normalizeCommentNode(node: any): MergedComment | null {
  if (!node || typeof node !== "object" || node.commentId == null) return null;

  const typename: string | undefined = node.__typename;
  const looksOffChain =
    node.commentedAt != null || (node.text != null && node.comment == null);

  const offChain =
    typename === "GraphQLOffChainComment" ||
    (typename == null && looksOffChain);
  // GraphQLComment and GraphQLBackfilledComment share the on-chain field set.
  const onChain =
    typename === "GraphQLComment" ||
    typename === "GraphQLBackfilledComment" ||
    (typename == null && !looksOffChain);

  if (offChain) {
    const commentedAtMs = Date.parse(node.commentedAt);
    return {
      commentId: node.commentId,
      offChain: true,
      text: node.text ?? "",
      timestamp: Number.isNaN(commentedAtMs)
        ? 0
        : Math.floor(commentedAtMs / 1000),
      handle: node.profile?.handle ?? undefined,
      sparkCount: node.sparkCount ?? 0,
      replyCount: node.replies?.count ?? 0,
    };
  }

  if (onChain) {
    return {
      commentId: node.commentId,
      offChain: false,
      text: node.comment ?? "",
      // On-chain timestamps are unix seconds already.
      timestamp: node.timestamp ?? 0,
      handle: node.userProfile?.handle ?? undefined,
      authorAddress: node.userAddress ?? undefined,
      // The merged feed omits the spark count on on-chain comments.
      sparkCount: node.sparkCount ?? 0,
      replyCount: node.replies?.count ?? 0,
    };
  }

  // `__typename` is present but unrecognized — a genuinely unknown node type.
  return null;
}

/**
 * Fetch a page of a coin's comments merged from on-chain, backfilled, and
 * off-chain sources, newest-first under a single cursor. Backed by the
 * coins-SDK's `getCoinMergedComments` (public, API-key auth); the older
 * `getCoinComments` only returns the on-chain `zoraComments` connection and
 * can't see off-chain comments. Throws with the API's message on failure.
 */
export async function listCoinComments(params: {
  chainId: number;
  address: string;
  first: number;
  after?: string;
}): Promise<MergedCommentsPage> {
  // Typed loosely: the hey-api RequestResult union doesn't narrow cleanly for a
  // plain `{ data, error }` destructure, and the node shape is normalized below.
  const result: any = await getCoinMergedComments({
    address: params.address,
    chain: params.chainId,
    count: params.first,
    after: params.after,
  });

  if (result?.error) {
    throw new Error(
      typeof result.error === "string"
        ? result.error
        : JSON.stringify(result.error),
    );
  }

  const connection = result?.data?.zora20Token?.comments;
  const edges: any[] = connection?.edges ?? [];
  const comments = edges
    .map((e) => normalizeCommentNode(e?.node))
    .filter((c): c is MergedComment => c !== null);

  return {
    comments,
    totalCount: connection?.count ?? comments.length,
    nextCursor: connection?.pageInfo?.hasNextPage
      ? (connection.pageInfo.endCursor ?? undefined)
      : undefined,
  };
}
/* eslint-enable @typescript-eslint/no-explicit-any */
