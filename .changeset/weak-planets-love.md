---
"@zoralabs/zora-1155-contracts": minor
---

Creator reward recipient can now be defined on a token by token basis.  This allows for multiple creators to collaborate on a contract and each to receive rewards for the token they created.  The royaltyRecipient storage field is now used to determine the creator reward recipient for each token. If that's not set for a token, it falls back to use the contract wide fundsRecipient.
