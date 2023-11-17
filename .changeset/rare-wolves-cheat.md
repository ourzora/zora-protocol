---
"@zoralabs/protocol-sdk": patch
---

### Changes to `preminter`

* `isValidSignature` now takes either v1 or v2 of a premint config, along with the premint config version. and both recovers the signer address and validates if the signer can create a premint on the given contract.

### Changes to PremintClient

sdk now supports creating and signing premints for v2 of Premint Config:

* `preminter.isValidSignature` 
* new function `preminter.supportsPremintVersion` which checks if a given token contract supports a given premint config version
* new function `preminter.recoverCreatorFromCreatorAttribution` which recovers the creator address from a `CreatorAttribution` event
* `preminter.premintTypedDataDefinition` now takes a premint config version, and returns the correct typed data definition for that version

* premint client methods now work with both v1 and v2 of the premint config, and takes an additional premint config version parameter