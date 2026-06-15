---
"@zoralabs/cli": patch
---

Reuse Privy sessions instead of re-running Sign-In-With-Ethereum for every agent operation.

Privy rate-limits the SIWE `authenticate` endpoint (~60 calls/week per app), which agents could exhaust by re-signing in for each new ~1h access token. The CLI now caches the Privy session and, once the access token expires, exchanges the refresh token at Privy's sessions endpoint for a fresh one — only falling back to a full SIWE sign-in when there is no cached session or the refresh is rejected. Agent onboarding likewise reuses the cached session while waiting for the embedded wallet to appear rather than re-authenticating on each poll.
