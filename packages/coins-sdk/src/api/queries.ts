import {
  GetCoinCommentsData,
  GetCoinCommentsResponse,
  GetCoinData,
  GetCoinResponse,
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

type APIQueryDataResponse<T> = Promise<{ data?: T }>;

export type { APIQueryDataResponse };

type GetCoinQuery = GetCoinData["query"];
export type { GetCoinQuery };
export type { GetCoinResponse } from "../client/types.gen";

export const getCoin = async (
  query: GetCoinQuery,
): Promise<{ data?: GetCoinResponse }> => {
  return await getCoinSDK({
    query,
    meta: getApiKeyMeta(),
  });
};

type GetCoinsQuery = {
  coinAddresses: string[];
  chainId?: number;
};
export type { GetCoinsQuery };
export type { GetCoinsResponse } from "../client/types.gen";

export const getCoins = async ({
  coinAddresses,
  chainId,
}: GetCoinsQuery): APIQueryDataResponse<GetCoinsResponse> => {
  return await getCoinsSDK({
    query: {
      coins: coinAddresses.map((collectionAddress) => ({
        chainId,
        collectionAddress,
      })),
    },
    meta: getApiKeyMeta(),
  });
};

type GetCoinCommentsQuery = GetCoinCommentsData["query"];
export type { GetCoinCommentsQuery };
export type { GetCoinCommentsResponse } from "../client/types.gen";

export const getCoinComments = async (
  query: GetCoinCommentsQuery,
): APIQueryDataResponse<GetCoinCommentsResponse> => {
  return await getCoinCommentsSDK({
    query,
    meta: getApiKeyMeta(),
  });
};

type GetProfileQuery = GetProfileData["query"];
export type { GetProfileQuery };
export type { GetProfileResponse } from "../client/types.gen";

export const getProfile = async (
  query: GetProfileQuery,
): APIQueryDataResponse<GetProfileResponse> => {
  return await getProfileSDK({
    query,
    meta: getApiKeyMeta(),
  });
};

type GetProfileBalancesQuery = GetProfileBalancesData["query"];
export type { GetProfileBalancesQuery };
export type { GetProfileBalancesResponse } from "../client/types.gen";

export const getProfileBalances = async (
  query: GetProfileBalancesData["query"],
) => {
  return await getProfileBalancesSDK({
    query,
    meta: getApiKeyMeta(),
  });
};
