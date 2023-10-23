---
"@zoralabs/zora-1155-contracts": minor
---

Premint v2 - for add new signature, where createReferral can be specified.  ZoraCreator1155PremintExecutor recognizes new version of the signature, and still works with the v1 (legacy) version of the signature.  1155 contract has been updated to now take abi encoded premint config, premint config version, and send it to an external library to decode the config, the signer, and setup actions.

changes to `ZoraCreator1155PremintExecutorImpl`:
* new function `premintV1` - takes a premint v1 signature and executed a premint, with added functionality of being able to specify mint referral and mint recipient
* new function `premintV2` - takes a premint v2 signature and executes a premint, with being able to specify mint referral and mint recipient
* deprecated function `premint` - call `premintV1` instead