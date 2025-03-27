import { getExplore as getExploreSDK } from "../client/sdk.gen";
import type { GetExploreData, GetExploreResponse } from "../client/types.gen";
import { getApiKeyMeta } from "./api-key";
import { RequestOptionsType } from "./query-types";

/**
 * The inner type for the explore queries that omits listType.
 * This is used to create the query object for the explore queries.
 */
export type QueryRequestType = Omit<GetExploreData["query"], "listType">;

type ExploreResponse = { data?: GetExploreResponse };

export type ListType = GetExploreData["query"]["listType"];

export type { ExploreResponse };

export type { GetExploreData };

/**
 * Creates an explore query with the specified list type
 */
const createExploreQuery = (
  query: QueryRequestType,
  listType: ListType,
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  getExploreSDK({
    ...options,
    query: { ...query, listType },
    meta: getApiKeyMeta(),
  });

/** Get top gaining coins */
export const getCoinsTopGainers = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TOP_GAINERS", options);

/** Get coins with highest 24h volume */
export const getCoinsTopVolume24h = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TOP_VOLUME_24H", options);

/** Get most valuable coins */
export const getCoinsMostValuable = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "MOST_VALUABLE", options);

/** Get newly created coins */
export const getCoinsNew = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> => createExploreQuery(query, "NEW", options);

/** Get recently traded coins */
export const getCoinsLastTraded = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "LAST_TRADED", options);

/** Get recently traded unique coins */
export const getCoinsLastTradedUnique = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "LAST_TRADED_UNIQUE", options);
