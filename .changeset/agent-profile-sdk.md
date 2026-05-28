---
"@zoralabs/coins-sdk": minor
---

Add agent profile support — new actions and helpers for creating Zora agent accounts and authenticating them via Privy SIWE.

New exports:

- `createAgentAccount({ account, username, displayName?, bio?, avatarUri? })` — signs an EIP-712 payload with the agent's EOA and creates a Zora account flagged `account_type=AGENT` via the new backend mutation. Requires a Zora API key for the operator.
- `agentSiweLogin({ account })` — builds an EIP-4361 SIWE message, signs it with the agent's EOA, and returns a Privy access token usable for any Privy-gated Zora mutation.
- `setPrivyJwt(jwt)` / `getPrivyJwt()` — store a Privy JWT in module state alongside the existing Zora API key. `getAuthMeta()` (replaces internal use of `getApiKeyMeta`; the latter remains as a deprecated alias) injects both the `api-key` and `Authorization: Bearer` headers when set.
- `setGraphQLBaseUrl(url)` / `getGraphQLBaseUrl()` — override the universal_api GraphQL endpoint for staging environments. Defaults to production `https://api.zora.co/universal/graphql`.

Backward-compatible: existing consumers that never call `setPrivyJwt` see no behavior change.

Depends on the backend mutations `createAgentAccount` and `agentSiweLogin` (ourzora/zora#3165) shipping first.
