import {
  getExplore as getExploreSDK,
  getTrendCoin as getTrendCoinSDK,
  getTrendsByName as getTrendsByNameSDK,
} from "../client/sdk.gen";
import type {
  GetExploreData,
  GetExploreResponse,
  GetTrendCoinData,
  GetTrendCoinResponse,
  GetTrendsByNameData,
  GetTrendsByNameResponse,
} from "../client/types.gen";
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

export type TrendCoinResponse = { data?: GetTrendCoinResponse };

export type TrendsByNameResponse = { data?: GetTrendsByNameResponse };

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
    ...getApiKeyMeta(),
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

export const getCreatorCoins = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "NEW_CREATORS", options);

export const getMostValuableCreatorCoins = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "MOST_VALUABLE_CREATORS", options);

export const getExploreTopVolumeCreators24h = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TOP_VOLUME_CREATORS_24H", options);

export const getExploreTopVolumeAll24h = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TOP_VOLUME_ALL_24H", options);

export const getExploreNewAll = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> => createExploreQuery(query, "NEW_ALL", options);

export const getExploreFeaturedCreators = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "FEATURED_CREATORS", options);

export const getExploreFeaturedVideos = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "FEATURED_VIDEOS", options);

/** Get trending coins across all types */
export const getTrendingAll = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TRENDING_ALL", options);

/** Get trending creator coins */
export const getTrendingCreators = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TRENDING_CREATORS", options);

/** Get trending posts */
export const getTrendingPosts = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TRENDING_POSTS", options);

/** Get most valuable trend coins */
export const getMostValuableTrends = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "MOST_VALUABLE_TRENDS", options);

/** Get new trend coins */
export const getNewTrends = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> => createExploreQuery(query, "NEW_TRENDS", options);

/** Get top volume trend coins (24h) */
export const getTopVolumeTrends24h = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TOP_VOLUME_TRENDS_24H", options);

/** Get trending trend coins */
export const getTrendingTrends = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "TRENDING_TRENDS", options);

/** Get most valuable coins across all types */
export const getMostValuableAll = (
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> =>
  createExploreQuery(query, "MOST_VALUABLE_ALL", options);

/** Look up a single trend coin by ticker (case-insensitive) */
export const getTrend = (
  query: GetTrendCoinData["query"],
  options?: RequestOptionsType<GetTrendCoinData>,
): Promise<TrendCoinResponse> =>
  getTrendCoinSDK({
    ...options,
    query,
    ...getApiKeyMeta(),
  });

/** Search trend coins by name, with fuzzy search (paginated) */
export const getTrends = (
  query: GetTrendsByNameData["query"],
  options?: RequestOptionsType<GetTrendsByNameData>,
): Promise<TrendsByNameResponse> =>
  getTrendsByNameSDK({
    ...options,
    query,
    ...getApiKeyMeta(),
  });

/** Generic explore query for any list type */
export const getExploreList = (
  listType: ListType,
  query: QueryRequestType = {},
  options?: RequestOptionsType<GetExploreData>,
): Promise<ExploreResponse> => createExploreQuery(query, listType, options);
