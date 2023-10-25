---
"@zoralabs/zora-1155-contracts": patch
---

Added method `IZoraCreator1155PremintExecutor.supportedPremintSignatureVersion(contractAddress)` that tells what version of the premint signature the contract supports, and added corresponding method `ZoraCreator1155Impl.supportedPremintSignatureVersion()` to fetch supported version.  If premint not supported, returns 0.