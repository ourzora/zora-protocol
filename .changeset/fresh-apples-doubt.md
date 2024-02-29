---
"@zoralabs/zora-1155-contracts": patch 
---

- `ZoraCreator1155PremintExecutorImpl` and `ZoraCreator1155Impl` support EIP-1271 based signatures for premint token creation, by taking in an extra param indicating the signing contract, and if that parameter is passed, calling a function on that contract address to validate the signature.  EIP-1271 is not supported with PremintV1 signatures.
- `ZoraCreator1155Impl` splits out `supportsInterface` check for premint related functionality into two separate interfaces to check for, allowing each interface to be updated independently.  
