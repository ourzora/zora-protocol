---
"@zoralabs/limit-orders": patch
---

Fix router-based limit order fills to use correct currency direction

Fixed bug in SwapWithLimitOrders where router fallback incorrectly inverted the currency direction parameter when calling `_fillOrders`. This caused orders to be skipped when the hook doesn't support limit order fills. The router now correctly passes `isCoinCurrency0` instead of `!isCoinCurrency0`, ensuring fills occur in the proper direction.
