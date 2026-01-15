---
"@zoralabs/limit-orders": patch
---

Fix limit order fill direction to derive from actual tick movement

Fixed limit order filling in `ZoraV4CoinHook` by deriving the fill direction from actual tick movement instead of using the swap direction parameter. The hook now only attempts to fill limit orders when there's an actual tick change, and determines the currency direction based on the comparison between before and after swap ticks. This ensures orders are filled correctly regardless of swap direction.