---
"@zoralabs/coins": minor
"@zoralabs/coins-deployments": patch
"@zoralabs/protocol-deployments": patch
---

Add TrendCoin support

- New `TrendCoin` contract: 100% supply in liquidity pool, 0% swap fees
- `deployTrendCoin` factory method with ticker uniqueness enforcement and post-deploy hook support
- Owner-configurable pool parameters via `setTrendCoinPoolConfig()`
- Metadata manager role for updatable contract URIs
- Ticker validation and URI encoding for trend coin symbols
