// This file is auto-generated by @hey-api/openapi-ts

import type {
  Options as ClientOptions,
  TDataShape,
  Client,
} from "@hey-api/client-fetch";
import type {
  GetCoinData,
  GetCoinResponse,
  GetCoinCommentsData,
  GetCoinCommentsResponse,
  GetCoinsData,
  GetCoinsResponse,
  GetExploreData,
  GetExploreResponse,
  GetProfileData,
  GetProfileResponse,
  GetProfileBalancesData,
  GetProfileBalancesResponse,
} from "./types.gen";
import { client as _heyApiClient } from "./client.gen";

export type Options<
  TData extends TDataShape = TDataShape,
  ThrowOnError extends boolean = boolean,
> = ClientOptions<TData, ThrowOnError> & {
  /**
   * You can provide a client instance returned by `createClient()` instead of
   * individual options. This might be also useful if you want to implement a
   * custom client.
   */
  client?: Client;
  /**
   * You can pass arbitrary values through the `meta` object. This can be
   * used to access values that aren't defined as part of the SDK function.
   */
  meta?: Record<string, unknown>;
};

/**
 * zoraSDK_coin query
 */
export const getCoin = <ThrowOnError extends boolean = false>(
  options: Options<GetCoinData, ThrowOnError>,
) => {
  return (options.client ?? _heyApiClient).get<
    GetCoinResponse,
    unknown,
    ThrowOnError
  >({
    url: "/coin",
    ...options,
  });
};

/**
 * zoraSDK_coinComments query
 */
export const getCoinComments = <ThrowOnError extends boolean = false>(
  options: Options<GetCoinCommentsData, ThrowOnError>,
) => {
  return (options.client ?? _heyApiClient).get<
    GetCoinCommentsResponse,
    unknown,
    ThrowOnError
  >({
    url: "/coinComments",
    ...options,
  });
};

/**
 * zoraSDK_coins query
 */
export const getCoins = <ThrowOnError extends boolean = false>(
  options: Options<GetCoinsData, ThrowOnError>,
) => {
  return (options.client ?? _heyApiClient).get<
    GetCoinsResponse,
    unknown,
    ThrowOnError
  >({
    url: "/coins",
    ...options,
  });
};

/**
 * zoraSDK_explore query
 */
export const getExplore = <ThrowOnError extends boolean = false>(
  options: Options<GetExploreData, ThrowOnError>,
) => {
  return (options.client ?? _heyApiClient).get<
    GetExploreResponse,
    unknown,
    ThrowOnError
  >({
    url: "/explore",
    ...options,
  });
};

/**
 * zoraSDK_profile query
 */
export const getProfile = <ThrowOnError extends boolean = false>(
  options: Options<GetProfileData, ThrowOnError>,
) => {
  return (options.client ?? _heyApiClient).get<
    GetProfileResponse,
    unknown,
    ThrowOnError
  >({
    url: "/profile",
    ...options,
  });
};

/**
 * zoraSDK_profileBalances query
 */
export const getProfileBalances = <ThrowOnError extends boolean = false>(
  options: Options<GetProfileBalancesData, ThrowOnError>,
) => {
  return (options.client ?? _heyApiClient).get<
    GetProfileBalancesResponse,
    unknown,
    ThrowOnError
  >({
    url: "/profileBalances",
    ...options,
  });
};
