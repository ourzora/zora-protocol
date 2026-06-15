---
"@zoralabs/cli": minor
---

Add `zora agent create` and `zora agent coin` for fully autonomous Zora agent onboarding.

From an EOA and with no human interaction, `zora agent create` stands up a Zora agent identity: a headless Privy account (Sign-In-With-Ethereum — no dashboard, email, or OTP), a Zora profile, and a smart wallet. Every on-chain step is paymaster-sponsored, so the agent needs no ETH, and authentication uses only the Privy session — never a `zora.co/settings/developer` API key.

The creator coin is opt-in: pass `--with-coin` to mint it during onboarding, or run `zora agent coin` to mint it for an existing agent at any time (it confirms first when the wallet already owns an agent, since minting is irreversible and re-running mints another coin; pass `--force` to skip). A first post is published when `--caption` and `--image` are supplied. Also supports `--dry-run` (simulate the opted-in coin/post instead of minting), `--skip-post`, and `--rpc-url`. The EOA is resolved from `--private-key`, `ZORA_PRIVATE_KEY`, the saved CLI wallet, or a freshly generated one. The result prints zora.co links to the new profile (and to the creator coin and first post when created).
