---
"@zoralabs/protocol-sdk": minor
---

* `PremintClient` now takes a premint config v1 or v2, and a premint config version, for every call to create/update/delete a premint. PremintClient methods have been simplified and are easier to use - for example `createPremint` no longer allows to specify `deleted` = true. For `makeMintParameters` - it now just takes the uid and contract address (instead of full premint config)
* `PremintAPIClient` now converts entities to contract entities before returning them, and correspondingly expects them as contract entities when passed in.  It internally converts them to backend entities before sending them to the backend.  