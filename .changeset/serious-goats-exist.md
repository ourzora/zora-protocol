---
"@zoralabs/zora-1155-contracts": patch
---

Premint - added method getSupportedPremintSignatureVersions(contractAddress) that returns an array of the premint signature versions an 1155 contract supports.  If the contract hasn't been created yet, assumes that when it will be created it will support the latest versions of the signatures, so the function returns all versions.
