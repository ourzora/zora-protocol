import {
  SetCreateUploadJwtData,
  SetCreateUploadJwtResponse,
} from "../client/types.gen";
import { setCreateUploadJwt as setCreateUploadJwtSDK } from "../client/sdk.gen";
import { getApiKeyMeta } from "./api-key";
import { RequestOptionsType } from "./query-types";
import { RequestResult } from "@hey-api/client-fetch";

type SetCreateUploadJwtQuery = SetCreateUploadJwtData["body"];
export type { SetCreateUploadJwtQuery, SetCreateUploadJwtData };
export type { SetCreateUploadJwtResponse } from "../client/types.gen";

export const setCreateUploadJwt = async (
  body: SetCreateUploadJwtQuery,
  options?: RequestOptionsType<SetCreateUploadJwtData>,
): Promise<RequestResult<SetCreateUploadJwtResponse>> => {
  return await setCreateUploadJwtSDK({
    body,
    ...getApiKeyMeta(),
    ...options,
  });
};
