/**
 * Agent-account GraphQL operations.
 *
 * The Zora REST SDK is auto-generated from OpenAPI and uses `@hey-api/client-fetch`.
 * Agent mutations live on the universal_api GraphQL endpoint (`api.zora.co/universal/graphql`),
 * which is not part of the generated REST surface. Rather than introduce a
 * GraphQL client dependency for two mutations, we hand-write the fetch calls
 * here, mirroring the auth-header pattern from `api-key.ts`.
 *
 * The GraphQL base URL is independently configurable via `setGraphQLBaseUrl`
 * to support staging environments — `setApiBaseUrl` (the REST one) does not
 * cover this since the two services live at different hostnames.
 */

import { getAuthMeta } from "./api-key";

let graphqlUrl = "https://api.zora.co/universal/graphql";

/**
 * Override the GraphQL endpoint URL. Use in staging / dev environments where
 * the universal_api is hosted elsewhere. Defaults to production.
 */
export function setGraphQLBaseUrl(url: string) {
  graphqlUrl = url;
}

export function getGraphQLBaseUrl() {
  return graphqlUrl;
}

const CREATE_AGENT_ACCOUNT_MUTATION = `
mutation CreateAgentAccount($input: GraphQLAgentAccountInput!) {
  createAgentAccount(agentAccountInput: $input) {
    accountId
    username
    handle
    bio
    accountType
    displayName
    avatar { medium }
  }
}
`.trim();

const AGENT_SIWE_LOGIN_MUTATION = `
mutation AgentSiweLogin($input: GraphQLAgentSiweLoginInput!) {
  agentSiweLogin(agentSiweLoginInput: $input) {
    accessToken
    expiresAt
  }
}
`.trim();

export type CreateAgentAccountVariables = {
  walletAddress: `0x${string}`;
  username: string;
  signature: `0x${string}`;
  nonce: `0x${string}`;
  issuedAt: number;
  expiresAt: number;
  displayName?: string;
  bio?: string;
  avatarUri?: string;
};

export type CreateAgentAccountResponse = {
  accountId: string;
  username: string;
  handle: string;
  bio: string;
  accountType: "user" | "agent" | null;
  displayName: string | null;
  avatar: { medium: string | null } | null;
};

export type AgentSiweLoginVariables = {
  walletAddress: `0x${string}`;
  message: string;
  signature: `0x${string}`;
};

export type AgentSiweLoginResponse = {
  accessToken: string;
  expiresAt: number;
};

type GraphQLEnvelope<T> = {
  data?: T;
  errors?: Array<{ message: string; extensions?: Record<string, unknown> }>;
};

async function postGraphQL<TVars, TData>(
  query: string,
  variables: TVars,
): Promise<TData> {
  const meta = getAuthMeta();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...((meta as { headers?: Record<string, string> }).headers ?? {}),
  };

  const response = await fetch(graphqlUrl, {
    method: "POST",
    headers,
    body: JSON.stringify({ query, variables }),
  });

  if (!response.ok) {
    throw new Error(
      `Zora GraphQL request failed: ${response.status} ${response.statusText}`,
    );
  }

  const json = (await response.json()) as GraphQLEnvelope<TData>;
  if (json.errors && json.errors.length > 0) {
    throw new Error(json.errors[0]?.message ?? "Zora GraphQL request errored");
  }
  if (!json.data) {
    throw new Error("Zora GraphQL response missing data");
  }
  return json.data;
}

export async function createAgentAccountMutation(
  input: CreateAgentAccountVariables,
): Promise<CreateAgentAccountResponse> {
  const data = await postGraphQL<
    { input: CreateAgentAccountVariables },
    { createAgentAccount: CreateAgentAccountResponse }
  >(CREATE_AGENT_ACCOUNT_MUTATION, { input });
  return data.createAgentAccount;
}

export async function agentSiweLoginMutation(
  input: AgentSiweLoginVariables,
): Promise<AgentSiweLoginResponse> {
  const data = await postGraphQL<
    { input: AgentSiweLoginVariables },
    { agentSiweLogin: AgentSiweLoginResponse }
  >(AGENT_SIWE_LOGIN_MUTATION, { input });
  return data.agentSiweLogin;
}
