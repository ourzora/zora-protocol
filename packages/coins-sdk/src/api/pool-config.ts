import {
  getCreateContentPoolConfig as getCreateContentPoolConfigSDK,
  GetCreateContentPoolConfigData,
  GetCreateContentPoolConfigResponse,
} from "../client";
import { RequestOptionsType } from "./query-types";
import { RequestResult } from "@hey-api/client-fetch";

export const getCreateContentPoolConfig = async (
  query: GetCreateContentPoolConfigData["query"],
  options?: RequestOptionsType<GetCreateContentPoolConfigData>,
): Promise<RequestResult<GetCreateContentPoolConfigResponse>> => {
  return getCreateContentPoolConfigSDK({
    query,
    ...options,
  });
};
