---
"@zoralabs/cli": minor
---

Record the full agent identity in the wallet file after `zora agent create`.

Previously the wallet file (`~/.config/zora/wallet.json`) held only the agent's private key. It now also stores an `agent` block capturing the embedded wallet address, smart wallet address, owner EOA address, Privy DID, profile handle, and profile URL, plus the creation timestamp. The presence of this block marks the wallet as agent-owned. The smart wallet address is mirrored to the top-level field as well, so the trading commands resolve it automatically.

The identity is recorded only when the wallet file is the source of the signing key — a freshly generated wallet or the saved CLI wallet. Keys supplied via `--private-key` or `ZORA_PRIVATE_KEY` are never written to disk, and an unrelated saved wallet is never overwritten.
