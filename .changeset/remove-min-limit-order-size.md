---
"@zoralabs/limit-orders": patch
---

Remove fixed MIN_LIMIT_ORDER_SIZE threshold that made many tokens unusable. Limit orders now accept any positive amount instead of requiring at least 1e18 tokens, fixing compatibility issues with tokens using different decimal configurations.