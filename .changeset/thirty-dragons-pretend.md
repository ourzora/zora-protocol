---
"@zoralabs/zora-1155-contracts": patch
---

Added method `IZoraCreator1155PremintExecutor.supportedPremintSignatureVersions(contractAddress)` that tells what version of the premint signature the contract supports, and added corresponding method `ZoraCreator1155Impl.supportedPremintSignatureVersions()` to fetch supported version.  If premint not supported, returns an empty array.