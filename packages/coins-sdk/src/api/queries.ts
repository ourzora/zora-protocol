import {
  GetCoinCommentsData,
  GetCoinCommentsResponse,
  GetCoinData,
  GetCoinResponse,
  GetCoinsData,
  GetCoinsResponse,
  GetProfileBalancesData,
  GetProfileData,
  GetProfileResponse,
} from "../client/types.gen";
import {
  getCoin as getCoinSDK,
  getCoins as getCoinsSDK,
  getCoinComments as getCoinCommentsSDK,
  getProfile as getProfileSDK,
  getProfileBalances as getProfileBalancesSDK,
} from "../client/sdk.gen";
import { getApiKeyMeta } from "./api-key";
import { RequestOptionsType } from "./query-types";

type APIQueryDataResponse<T> = Promise<{ data?: T }>;

export type { APIQueryDataResponse };

type GetCoinQuery = GetCoinData["query"];
export type { GetCoinQuery, GetCoinData };
export type { GetCoinResponse } from "../client/types.gen";

export type CoinData = NonNullable<GetCoinResponse["zora20Token"]>;

export const getCoin = async (
  query: GetCoinQuery,
  options?: RequestOptionsType<GetCoinData>,
): Promise<{ data?: GetCoinResponse }> => {
  return await getCoinSDK({
    ...options,
    query,
    meta: getApiKeyMeta(),
  });
};

type GetCoinsQuery = {
  coinAddresses: string[];
  chainId?: number;
};
export type { GetCoinsQuery, GetCoinsData };
export type { GetCoinsResponse } from "../client/types.gen";

export const getCoins = async (
  { coinAddresses, chainId }: GetCoinsQuery,
  options?: RequestOptionsType<GetCoinsData>,
): APIQueryDataResponse<GetCoinsResponse> => {
  return await getCoinsSDK({
    query: {
      coins: coinAddresses.map((collectionAddress) => ({
        chainId,
        collectionAddress,
      })),
    },
    meta: getApiKeyMeta(),
    ...options,
  });
};

type GetCoinCommentsQuery = GetCoinCommentsData["query"];
export type { GetCoinCommentsQuery, GetCoinCommentsData };
export type { GetCoinCommentsResponse } from "../client/types.gen";

export const getCoinComments = async (
  query: GetCoinCommentsQuery,
  options?: RequestOptionsType<GetCoinCommentsData>,
): APIQueryDataResponse<GetCoinCommentsResponse> => {
  return await getCoinCommentsSDK({
    query,
    meta: getApiKeyMeta(),
    ...options,
  });
};

type GetProfileQuery = GetProfileData["query"];
export type { GetProfileQuery, GetProfileData };
export type { GetProfileResponse } from "../client/types.gen";

export const getProfile = async (
  query: GetProfileQuery,
  options?: RequestOptionsType<GetProfileData>,
): APIQueryDataResponse<GetProfileResponse> => {
  return await getProfileSDK({
    query,
    meta: getApiKeyMeta(),
    ...options,
  });
};

type GetProfileBalancesQuery = GetProfileBalancesData["query"];
export type { GetProfileBalancesQuery, GetProfileBalancesData };
export type { GetProfileBalancesResponse } from "../client/types.gen";

export const getProfileBalances = async (
  query: GetProfileBalancesData["query"],
  options?: RequestOptionsType<GetProfileBalancesData>,
) => {
  return await getProfileBalancesSDK({
    query,
    meta: getApiKeyMeta(),
    ...options,
  });
};
