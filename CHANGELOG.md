# @zoralabs/zora-1155-contracts

## 1.5.0

### Minor Changes

- 1bf2d52: Add TokenId to redeemInstructionsHashIsAllowed for Redeem Contracts
- a170f1f: - Patches the 1155 `callSale` function to ensure that the token id passed matches the token id encoded in the generic calldata to forward
  - Updates the redeem minter to v1.1.0 to support b2r per an 1155 token id

### Patch Changes

- b1dbb47: Fix types reference for package export
- 4cb56d4: - Ensures sales configs can only be updated for the token ids specified
  - Deprecates support with 'ZoraCreatorRedeemMinterStrategy' v1.0.1

## 1.4.0

### Minor Changes

- 5b3fafd: Change permission checks for contracts – fix allowing roles that are not admin assigned to tokenid 0 to apply those roles to any token in the contract.
- 9f6510d: Add support for rewards

  - Add new minting functions supporting rewards
  - Add new "rewards" library

## 1.3.3

### Patch Changes

- 498998f: Added pgn sepolia
  Added pgn mainnet
- cc3b55a: New base mainnet deploy
