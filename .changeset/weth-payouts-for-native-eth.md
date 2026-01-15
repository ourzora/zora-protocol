---
"@zoralabs/limit-orders": patch
---

Add WETH support for native ETH payouts in limit orders. When limit orders are filled or withdrawn with native ETH as the payout currency, the system now automatically wraps ETH into WETH before sending to recipients. This ensures compatibility with wallets and smart contracts that cannot receive native ETH directly, preventing transaction failures.

**Breaking Change**: The `ZoraLimitOrderBook` constructor now requires an additional `weth` parameter. This affects deployment scripts and deterministic address computation.