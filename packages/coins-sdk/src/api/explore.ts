import { getExplore as getExploreSDK } from "../client/sdk.gen";
import type { GetExploreData, GetExploreResponse } from "../client/types.gen";
import { Options } from "@hey-api/client-fetch";
import { getApiKeyMeta } from "./api-key";

/**
 * The inner type for the explore queries that omits listType.
 * This is used to create the query object for the explore queries.
 */
export type QueryInnerType = {
  query: Omit<GetExploreData["query"], "listType">;
} & Omit<GetExploreData, "query">;

type ExploreResponse = { data?: GetExploreResponse };

export type ListType = GetExploreData["query"]["listType"];

export type { ExploreResponse };

/**
 * Creates an explore query with the specified list type
 */
const createExploreQuery = <T extends boolean = false>(
  listType: ListType,
  options?: Options<QueryInnerType, T>,
): Promise<ExploreResponse> =>
  getExploreSDK({
    ...options,
    query: { ...options?.query, listType },
    meta: getApiKeyMeta(),
  });

/** Get top gaining coins */
export const getCoinsTopGainers = <T extends boolean = false>(
  options?: Options<QueryInnerType, T>,
): Promise<ExploreResponse> => createExploreQuery("TOP_GAINERS", options);

/** Get coins with highest 24h volume */
export const getCoinsTopVolume24h = <T extends boolean = false>(
  options?: Options<QueryInnerType, T>,
): Promise<ExploreResponse> => createExploreQuery("TOP_VOLUME_24H", options);

/** Get most valuable coins */
export const getCoinsMostValuable = <T extends boolean = false>(
  options?: Options<QueryInnerType, T>,
): Promise<ExploreResponse> => createExploreQuery("MOST_VALUABLE", options);

/** Get newly created coins */
export const getCoinsNew = <T extends boolean = false>(
  options?: Options<QueryInnerType, T>,
): Promise<ExploreResponse> => createExploreQuery("NEW", options);

/** Get recently traded coins */
export const getCoinsLastTraded = <T extends boolean = false>(
  options?: Options<QueryInnerType, T>,
): Promise<ExploreResponse> => createExploreQuery("LAST_TRADED", options);

/** Get recently traded unique coins */
export const getCoinsLastTradedUnique = <T extends boolean = false>(
  options?: Options<QueryInnerType, T>,
): Promise<ExploreResponse> =>
  createExploreQuery("LAST_TRADED_UNIQUE", options);
