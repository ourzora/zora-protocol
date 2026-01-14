---
"@zoralabs/limit-orders": patch
---

Remove unused settle negative deltas logic

- Remove redundant `_settleNegativeDeltas` function that was never executed
- Simplify limit order closure logic by removing unnecessary delta settlement
