---
"@zoralabs/zora-1155-contracts": minor
---

expanded rewards: added new platformReferral reward. 1155 mint fee increased to 0.00111 ether. `mintWithRewards` deprecated. `mint` now replaces mintWithRewards, and has been changed to take a `rewardsRecipient` array, containing, in order `mintReferral` and `platformReferral`
