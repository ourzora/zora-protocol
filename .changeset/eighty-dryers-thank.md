---
"@zoralabs/cli": patch
---

Decode Solidity revert errors into friendly trade messages

- Replace opaque "Execution reverted" messages with actionable guidance for 17 known contract errors
- Fix RPC transport to preserve JSON-RPC error code/data for proper viem error classification
