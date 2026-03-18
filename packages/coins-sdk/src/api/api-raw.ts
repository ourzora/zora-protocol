import { client } from "../client/client.gen";
import { getApiKeyMeta } from "./api-key";

export const apiGet = (path: string, data?: Record<string, unknown>) =>
  client.get({ url: path, query: data, ...getApiKeyMeta() });

export const apiPost = (path: string, data?: Record<string, unknown>) =>
  client.post({ url: path, body: data, ...getApiKeyMeta() });
