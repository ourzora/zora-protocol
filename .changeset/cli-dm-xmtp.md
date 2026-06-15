---
"@zoralabs/cli": minor
---

Add `zora dm` commands to read, send, and authorize Zora DMs over XMTP — `dm list`, `dm read <address>`, `dm send <address> "<message>"`, `dm requests`, and `dm approve`/`deny <address>`, all supporting `--json`.

DMs run from the user's shared Coinbase Smart Wallet inbox — the same inbox the web and mobile apps use — authenticated as their Zora identity via Privy. The CLI signs as a smart-wallet owner and obtains a Privy access token to enforce the new-conversation gate and register the installation. Running `zora agent create` provisions the smart wallet; until one exists, `zora dm` explains how to set it up.
