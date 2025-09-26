---
"@zoralabs/coins": patch
---

Fix LP position duplication when deploying coins.  If two positions are created with the same tick ranges, they are merged and stored as one position.  This reduces gas costs during swapping as there are less LP positions to iterate through when collecting fees.