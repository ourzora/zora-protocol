---
"@zoralabs/zora-1155-contracts": minor
---

Premint v2 - for add new signature, where createReferral can be specified.  ZoraCreator1155PremintExecutor recognizes new version of the signature, and still works with the v1 (legacy) version of the signature.  1155 contract has been updated to now take abi encoded premint config, premint config version, and send it to an external library to decode the config, the signer, and setup actions.