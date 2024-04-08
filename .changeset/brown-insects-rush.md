---
"@zoralabs/zora-1155-contracts": minor
"@zoralabs/mints-contracts": minor
---

- 1155 contracts use the MINTs contracts to get the mint fee, mint, and redeem a mint ticket upon minting.
- `ZoraCreator1155Impl` adds a new method `mintWithMints` that allows for minting with MINTs that are already owned.