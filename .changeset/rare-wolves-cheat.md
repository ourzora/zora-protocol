---
"@zoralabs/protocol-sdk": patch
---

### Changes to `preminter`

lower level `preminter.ts` now supports premint v2 by defining v2 typed data defintions.

* `isValidSignature` now takes either v1 or v2 of a premint config, along with the premint config version. and both recovers the signer address and validates if the signer can create a premint on the given contract.
* new function `premintTypedDataDefinition` which takes a premint config version and returns the signable typed data definition for that version
* new function `recoverCreatorFromCreatorAttribution` which recovers the creator address from a `CreatorAttribution` event
* new function `supportsPremintVersion` which checks if a given token contract supports a given premint config version
* new function `tryRecoverPremintSigner` which takes a premint config version and a premint signature, and tries to recover the signer address from the signature.  If the signature is invalid, it returns undefined.

### Changes to PremintClient

`PremintClient` creation, updating, and deletion now take both premint config v1 and v2, but currently rejects them until the backend api supports creating v2 premints.

* `isValidSignature` now just takes the data directly as a param, instead of `{data}`