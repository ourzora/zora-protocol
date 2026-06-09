---
"@zoralabs/cli": minor
---

Add `zora agent create` for headless agent onboarding.

From an EOA and with no human interaction, `zora agent create` creates a headless Privy account (Sign-In-With-Ethereum — no dashboard, email, or OTP) and a Zora profile. Authentication uses only the Privy session — never a `zora.co/settings/developer` API key. The EOA is resolved from `--private-key`, `ZORA_PRIVATE_KEY`, the saved CLI wallet, or a freshly generated one, and the command prints the profile handle plus a Privy access token to send as `Authorization: Bearer <token>`.
