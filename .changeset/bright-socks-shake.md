---
"@zoralabs/zora-1155-contracts": patch
---

- ZoraCreator1155Impl contract no longer has public facing function `computeFreeMintRewards` and `computePaidMintRewards`
- protocol rewards calculation logic has been refactored and moved from the RewardSplits contract to the ZoraCreator1155Impl itself to save on contract size.
- ZoraCreator1155Impl rewards splits are percentage based instead of a fixed value.  This % is calculated based on the total reward value. And is based on a % value nearly identical to the previous fixed value.
