---
"@zoralabs/coins": patch
---

Fix ETH settlement by adding missing sync before settle in V3ToV4SwapLib

Added a `poolManager.sync(inputCurrency)` call before settling when the input currency is ETH. This ensures the pool state is properly synchronized before the settlement occurs, making the behavior consistent with the ERC20 handling path which already includes this sync step.