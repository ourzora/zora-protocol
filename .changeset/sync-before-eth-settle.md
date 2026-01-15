---
"@zoralabs/limit-orders": patch
---

Fix native ETH settlement to prevent potential DoS by synchronizing pool manager state before settlement. This ensures accurate ETH balance tracking and prevents transaction failures when processing limit orders with native ETH.