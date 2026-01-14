---
"@zoralabs/limit-orders": patch
---

Fix maxFillCount bounds checking to always cap it at the default max fill count, event if a higher value is passed.