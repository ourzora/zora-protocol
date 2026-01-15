---
"@zoralabs/limit-orders": patch
---

Fix security vulnerability that allowed withdrawal of fillable limit orders. When a limit order becomes fillable due to market price crossing the limit price, users are now prevented from withdrawing the order and must execute it instead. This enforces proper market behavior and prevents users from backing out of orders that should be filled based on current market conditions.