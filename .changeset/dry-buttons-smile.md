---
"@zoralabs/protocol-sdk": minor
---

Changed how we determine which ERC20Z tokens have secondary royalties by querying the royalties contract directly instead of using the subgraph's secondaryActivated field.

BREAKING: The `withdrawRewards` and `getRewardsBalances` functions now require a `publicClient` parameter to query the royalties contract. Update your calls to include the publicClient when using these functions.
