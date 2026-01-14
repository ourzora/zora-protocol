---
"@zoralabs/limit-orders": patch
---

Refetch pool tick before filling each order to ensure accurate tick validation

Improved the limit order filling logic to prevent orders from being filled with stale tick data. The fix adds a current tick refresh before checking if an order has crossed the current tick price during the execution loop. This ensures that orders are only filled when they have actually crossed the current tick price, preventing incorrect fills due to price movements during the fill operation.