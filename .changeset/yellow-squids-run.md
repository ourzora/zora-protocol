---
"@zoralabs/zora-1155-contracts": minor
---

- Introduced a `reduceSupply` function allowing an approved minter or admin to reduce the supply for a given token id. New supply must be less than the current maxSupply, and greater than or equal to the total minted so far.
- Removed the deprecated `mintWithRewards` function
