---
"@zoralabs/zora-1155-contracts": patch
"@zoralabs/protocol-deployments": patch
"@zoralabs/premint-sdk": patch
---

created new package `protocol-deployments` that includes the deployed contract addresses. 

* 1155-contracts js no longer exports deployed addresses, just the abis
* premint-sdk imports deployed addresses from `protocol-deployments