---
"@zoralabs/limit-orders": patch
---

Fix CEI violation in limit order filling by moving order removal before external liquidity calls to prevent potential reentrancy issues