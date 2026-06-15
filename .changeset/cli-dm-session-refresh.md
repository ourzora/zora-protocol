---
"@zoralabs/cli": patch
---

Authenticate `zora dm` with the cached/refreshing Privy session.

DM authentication previously ran a full SIWE sign-in on every `zora dm` invocation — and on the background new-DM check that runs after other commands — which quickly burned through Privy's ~60/week SIWE rate limit and added a network round-trip to each command. DM now reuses the cached access token (refreshing it via the long-lived refresh token when expired) and only falls back to SIWE when neither is available, sharing the same session path as `zora agent` onboarding. A session served from the cached token carries no linked accounts, so when they're absent the smart wallet's embedded owner is recovered from the persisted agent identity rather than forcing a fresh sign-in.
