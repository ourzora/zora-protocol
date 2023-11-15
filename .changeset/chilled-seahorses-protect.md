---
"@zoralabs/protocol-sdk": patch
---

`MintClient.makePrepareMintTokenParams` has the following changes:
  * returns a `SimulateContractParams`, instead of an object containing it indexed by key
  * PublicClient as an optional argument


Internally, MintClient is refactored to extract some functionality into static helpers that could eventually be publicly exposed

