---
"@zoralabs/limit-orders": patch
---

Fix premature limit order fills due to Uniswap v4 tick boundary handling

Previously, limit orders for non-currency0 tokens could be filled prematurely when the current tick was exactly equal to the order's lower tick boundary. This fix ensures orders are only filled when the pool tick has fully crossed the order's range, preventing users from receiving fewer output tokens than intended.