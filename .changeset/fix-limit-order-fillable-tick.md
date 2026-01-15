---
"@zoralabs/limit-orders": patch
---

Fix limit order execution logic for correct tick queue placement

Fixed critical bug where limit orders were being enqueued at incorrect ticks, preventing proper execution. Currency0 orders now correctly execute when price rises to the upper tick, and Currency1 orders execute when price falls to the lower tick.