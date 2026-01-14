---
"@zoralabs/limit-orders": major
---

Add swap price data fields to SwapWithLimitOrdersExecuted event. The event now includes actual swap amounts (amount0 and amount1) and final sqrt price (sqrtPriceX96), while removing the redundant delta field. This breaking change provides more detailed swap information for indexers and frontends to track swaps with limit orders without requiring additional RPC calls.