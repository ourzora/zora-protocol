---
"@zoralabs/zora-1155-contracts": patch
"@zoralabs/mints-contracts": patch
---

- To support the MINTs contract passing the first minter as an argument to `premintV2WithSignerContract` - we add the field `firstMinter` to `premintV2WithSignerContract`, and then in the 1155 check that the firstMinter argument is not address(0) since it now can be passed in manually.


