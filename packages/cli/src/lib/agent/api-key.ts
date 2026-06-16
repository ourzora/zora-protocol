import { graphqlRequest } from "./zora-client.js";

const CREATE_API_KEY_MUTATION =
  "mutation CreateApiKeyMutation($apiKeyName: String!, $hosts: [String!]) { createApiKey(apiKeyName: $apiKeyName, hosts: $hosts) { apiKey }}";

export type ApiKey = `zora_api_${string}`;

export async function createApiKey(
  token: string,
  apiKeyName: string,
  hosts?: string[],
): Promise<ApiKey> {
  const { data, errors, status } = await graphqlRequest(
    token,
    CREATE_API_KEY_MUTATION,
    "CreateApiKeyMutation",
    { apiKeyName, hosts: hosts ?? null },
  );
  const apiKey = data?.createApiKey?.apiKey;
  if (apiKey) {
    return apiKey;
  }
  const lastError = errors?.[0]?.message ?? `HTTP ${status}`;
  throw new Error(`createApiKey failed: ${lastError}`);
}
