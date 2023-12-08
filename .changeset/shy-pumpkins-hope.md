---
"@zoralabs/zora-1155-contracts": patch
---

Support platform referral in premint executor; it can call the new mint function if it exists on the 1155 contract. Correspondingly, added a supportsInterface check to the 1155 contract for the new mint function.
