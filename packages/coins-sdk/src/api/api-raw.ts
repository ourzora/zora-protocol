import { client } from "../client/client.gen";
import { createConfig } from "@hey-api/client-fetch";
import { getApiKeyMeta } from "./api-key";

export const apiGet = (path: string, data?: Record<string, unknown>) =>
  client.get({ url: path, query: data, ...getApiKeyMeta() });

export const apiPost = (path: string, data?: Record<string, unknown>) =>
  client.post({ url: path, body: data, ...getApiKeyMeta() });

export const setApiBaseUrl = (baseUrl: string) => {
  client.setConfig(createConfig({ baseUrl }));
};
