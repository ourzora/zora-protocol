import { BASE_CHAIN_ID, graphqlRequest } from "./agent/zora-client.js";

/**
 * The signed-in account whose hidden-coin set was just mutated. The
 * add/remove mutations both return the viewer's `GraphQLAccountProfile`, so we
 * surface just enough to confirm the change applied.
 */
export interface HideResult {
  profileId: string;
  handle: string;
}

type HideField = "addHiddenCreation" | "removeHiddenCreation";

const HIDE_MUTATION =
  "mutation CliHideCoin($input: GraphQLHiddenCreationInput!) { addHiddenCreation(input: $input) { id profileId handle } }";

const UNHIDE_MUTATION =
  "mutation CliUnhideCoin($input: GraphQLHiddenCreationInput!) { removeHiddenCreation(input: $input) { id profileId handle } }";

/**
 * Add or remove a coin from the viewer's hidden list via the Zora universal
 * GraphQL API, authenticated by the caller's Privy access token (the viewer
 * context the mutation needs). Hiding is keyed by collection address on a
 * specific chain; coins are single-token ERC20s, so `tokenId` is null. Both
 * mutations return the viewer's account profile, so parsing is shared — only
 * the query, operation name, and response field differ.
 */
async function mutateHide(
  token: string,
  coinAddress: string,
  chainId: number,
  mutation: string,
  operationName: string,
  field: HideField,
): Promise<HideResult> {
  const { data, errors, status } = await graphqlRequest(
    token,
    mutation,
    operationName,
    {
      input: {
        chainId,
        collectionAddress: coinAddress,
        tokenId: null,
      },
    },
  );
  const profile = data?.[field];
  if (profile?.profileId) {
    return {
      profileId: profile.profileId,
      handle: profile.handle ?? profile.profileId,
    };
  }
  const lastError = errors?.[0]?.message ?? `HTTP ${status}`;
  throw new Error(`${field} failed: ${lastError}`);
}

/** Hide a coin (by address, on `chainId`) from the viewer's holdings and profile. */
export function hideCoin(
  token: string,
  coinAddress: string,
  chainId: number = BASE_CHAIN_ID,
): Promise<HideResult> {
  return mutateHide(
    token,
    coinAddress,
    chainId,
    HIDE_MUTATION,
    "CliHideCoin",
    "addHiddenCreation",
  );
}

/** Unhide a previously hidden coin (by address, on `chainId`) for the viewer. */
export function unhideCoin(
  token: string,
  coinAddress: string,
  chainId: number = BASE_CHAIN_ID,
): Promise<HideResult> {
  return mutateHide(
    token,
    coinAddress,
    chainId,
    UNHIDE_MUTATION,
    "CliUnhideCoin",
    "removeHiddenCreation",
  );
}
