---
"@zoralabs/coins-contracts": patch
---

Fix stale PoolKey mapping after migration in ZoraV4CoinHook

Delete the old pool key from the poolCoins mapping after successful liquidity migration to prevent future operations on migrated pools.
