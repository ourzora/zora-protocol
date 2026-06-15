---
"@zoralabs/cli": patch
---

Include the wallet address in `zora balance --json`, `zora balance spendable --json`, and `zora balance coins --json` output.

The JSON output now contains a top-level `walletAddress` field alongside `wallet`, so it's clear which wallet the token balances belong to.
