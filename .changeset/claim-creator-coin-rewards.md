---
"@zoralabs/cli": minor
---

Add `zora claim` to claim vested creator coin rewards

Creators earn a vesting allocation of their creator coin that releases linearly over time. `zora claim` shows the pending amount and releases it on-chain to the payout recipient in a single step, defaulting to the wallet's own creator coin (or `--coin <address>` for a specific one).
