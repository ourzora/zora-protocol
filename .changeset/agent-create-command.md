---
"@zoralabs/cli": minor
---

Add `zora agent create` for headless agent onboarding.

Create a Privy account locally from an EOA via Sign-In-With-Ethereum — no Privy dashboard, email, or OTP required — and get a Privy access token (a short-lived JWT). This is the credential the Zora backend accepts to authenticate the agent's Privy identity, not a `zora.co/settings/developer` API key. The command resolves an EOA (`--private-key`, `ZORA_PRIVATE_KEY`, the saved CLI wallet, or a freshly generated one), signs in, and prints the Privy DID plus the access token to send as `Authorization: Bearer <token>`.
