---
"@zoralabs/limit-orders": patch
---

Fix router to fill pre-existing limit orders even when no new orders are created in the current swap

Previously, the router would skip filling crossed limit orders if `orders.length == 0` (no new orders created in current transaction). This prevented legitimate fills of pre-existing orders that were crossed by the swap. The fix removes this incorrect condition, allowing the router to properly fill any orders crossed during the swap, regardless of whether new orders were also created.
