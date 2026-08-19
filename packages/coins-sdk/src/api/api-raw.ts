import { client } from "../client/client.gen";
import { createConfig } from "@hey-api/client-fetch";
import { getApiKeyMeta } from "./api-key";

export const apiGet = (path: string, data?: Record<string, unknown>) =>
  client.get({ url: path, query: data, ...getApiKeyMeta() });

export const apiPost = (path: string, data?: Record<string, unknown>) =>
  client.post({ url: path, body: data, ...getApiKeyMeta() });

export const apiUrl = (path: string) => {
  const baseUrl = client.getConfig().baseUrl ?? "";
  // normalize the join boundary so we never end up with double slashes
  // (or a missing slash) between the base URL and the path
  const normalizedBase = baseUrl.replace(/\/+$/, "");
  const normalizedPath = path.replace(/^\/+/, "");
  return `${normalizedBase}/${normalizedPath}`;
};

export const setApiBaseUrl = (baseUrl: string) => {
  client.setConfig(createConfig({ baseUrl }));
};
