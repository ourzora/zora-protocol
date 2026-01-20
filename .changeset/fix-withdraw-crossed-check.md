---
"@zoralabs/limit-orders": patch
---

Fix withdraw crossed order check to use consistent logic with fills. The `hasCrossed` check for currency1 orders now uses strict `<` comparison instead of `<=`, preventing false positives at the tick boundary. Consolidated `hasCrossed` and `currentPoolTick` helpers into `LimitOrderCommon` for shared use across fill and withdraw paths.
