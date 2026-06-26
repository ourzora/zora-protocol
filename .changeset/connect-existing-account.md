---
"@zoralabs/cli": minor
---

Add `zora wallet connect` to control an existing Zora account from the CLI.

Paste the private key that controls a Zora account (the one exported from Zora's Privy-backed wallet settings) and the CLI derives the owner EOA, auto-discovers the account's Coinbase Smart Wallet on-chain — it's deployed deterministically from its owner, so no address lookup is needed — verifies the key owns it, and saves both the key and the smart wallet address to `wallet.json`. After connecting, `buy`, `sell`, and `coin create` act as the real account rather than the bare EOA.

This fills the gap left by `setup` / `wallet configure --import`, which store only the EOA and therefore trade from the key directly instead of the user's account ("found my EOA but not my smart wallet"). Pass `--smart-wallet <addr>` to override discovery for a non-standard owner set; overwriting a wallet that owns an agent is blocked by the same irreversible-overwrite guard as `setup --force`.
