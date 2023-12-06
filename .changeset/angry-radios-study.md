---
"@zoralabs/zora-1155-contracts": patch
"@zoralabs/protocol-sdk": patch
---

* For premintV1 and V2 - mintReferrer has been changed to an array `mintRewardsRecipients` - which the first element in array is `mintReferral`, and second element is `platformReferral`.  `platformReferral is not used by the premint contract yet`.
