---
"@zoralabs/zora-1155-contracts": patch
"@zoralabs/protocol-deployments": patch
---

Updated the 1155 Implementation reduceSupply function to be gated to the `TimedSaleStrategy` constructor argument 
to ensure markets are launched when desired.    
