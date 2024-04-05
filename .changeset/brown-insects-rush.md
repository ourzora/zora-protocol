---
"@zoralabs/zora-1155-contracts": minor
"@zoralabs/mints-contracts": minor
---

- 1155 contracts use the MINTs contract to get the mint fee, mint, and redeem a mint ticket upon minting.
- Added `premintWithMints` the `ZoraCreatorPremintExecutorImpl`, enabling it to support preminting with already owned MINTs
- `ZoraMintsImpl` supports collecting zora creator 1155 nfts with new `collect` and `collectPremint` methods. `redeemBatch` is also added.
- `ZoraCreator1155Impl` adds a new method `mintWithMints` that allows for minting with MINTs that are already owned.