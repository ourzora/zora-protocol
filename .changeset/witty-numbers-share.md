---
"@zoralabs/zora-1155-contracts": minor
---

- Patches the 1155 `callSale` function to ensure that the token id passed matches the token id encoded in the generic calldata to forward
- Updates the redeem minter to v1.1.0 to support b2r per an 1155 token id
