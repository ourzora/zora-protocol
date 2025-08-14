import {
  PostCreateContentData,
  PostCreateContentResponse,
} from "../client/types.gen";
import { postCreateContent as postCreateContentSDK } from "../client/sdk.gen";
import { getApiKeyMeta } from "./api-key";
import { RequestOptionsType } from "./query-types";
import { RequestResult } from "@hey-api/client-fetch";

type PostCreateContentQuery = PostCreateContentData["body"];
export type { PostCreateContentQuery, PostCreateContentResponse };

export type CoinCreateData = NonNullable<PostCreateContentResponse>;

export const postCreateContent = async (
  body: PostCreateContentQuery,
  options?: RequestOptionsType<PostCreateContentData>,
): Promise<RequestResult<PostCreateContentResponse>> => {
  return await postCreateContentSDK({
    ...options,
    body,
    ...getApiKeyMeta(),
  });
};
