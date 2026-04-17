import {
  GetProfileBySocialHandleData,
  GetProfileBySocialHandleResponse,
} from "../client/types.gen";
import { getProfileBySocialHandle as getProfileBySocialHandleSDK } from "../client/sdk.gen";
import { getApiKeyMeta } from "./api-key";
import { RequestOptionsType } from "./query-types";
import { RequestResult } from "@hey-api/client-fetch";

type GetProfileBySocialHandleQuery = GetProfileBySocialHandleData["query"];
export type { GetProfileBySocialHandleQuery, GetProfileBySocialHandleData };
export type { GetProfileBySocialHandleResponse } from "../client/types.gen";

export const getProfileBySocialHandle = async (
  query: GetProfileBySocialHandleQuery,
  options?: RequestOptionsType<GetProfileBySocialHandleData>,
): Promise<RequestResult<GetProfileBySocialHandleResponse>> => {
  return await getProfileBySocialHandleSDK({
    ...options,
    query,
    ...getApiKeyMeta(),
  });
};
