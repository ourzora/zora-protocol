---
"@zoralabs/cli": patch
---

Show the smart wallet address in `zora wallet info`.

`zora wallet info` previously only displayed the owner EOA derived from the private key, even when the wallet had a smart wallet (Zora account) configured. It now leads with the smart wallet address — the user-facing wallet that holds coins and posts — and shows the owner EOA beneath it, falling back to the EOA only for wallets that have no smart wallet yet. The smart wallet is read from `ZORA_SMART_WALLET_ADDRESS` when set, otherwise from the stored wallet file, and JSON output gains explicit `smartWalletAddress` and `ownerAddress` fields.
