---
"@zoralabs/cli": minor
---

Add `zora agent create` for fully autonomous Zora agent onboarding.

From an EOA and with no human interaction, `zora agent create` stands up a complete Zora agent identity: a headless Privy account (Sign-In-With-Ethereum — no dashboard, email, or OTP), a Zora profile, a smart wallet, a creator coin, and a first post. Every on-chain step is paymaster-sponsored, so the agent needs no ETH, and authentication uses only the Privy session — never a `zora.co/settings/developer` API key. Supports `--dry-run` (create the account, profile, and smart wallet, but simulate the coin + post rather than minting), `--skip-coin`, `--skip-post`, and `--rpc-url`. The EOA is resolved from `--private-key`, `ZORA_PRIVATE_KEY`, the saved CLI wallet, or a freshly generated one. The result prints zora.co links to the new profile, creator coin, and first post.
