---
"@zoralabs/limit-orders": patch
---

Remove unnecessary Permit2Payments inheritance and use direct PERMIT2 immutable reference instead. This simplifies the contract structure by eliminating unused inherited functions while maintaining identical functionality.