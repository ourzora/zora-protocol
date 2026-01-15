---
"@zoralabs/limit-orders": patch
---

Simplify limit order filling logic by deriving fill direction from tick movement. The system now automatically determines the correct currency direction based on tick changes (increasing tick = currency0, decreasing tick = currency1) instead of using complex tick sorting logic. This fix resolves issues where limit orders would revert when ticks were in unexpected order.