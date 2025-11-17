---
"@zoralabs/protocol-deployments": patch
---

Reduced hook code size by removing extra liquidity minting step during migration. Small leftover token amounts from rounding are now left as burned rather than being minted into the last position.
