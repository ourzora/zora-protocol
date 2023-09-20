# @zoralabs/zora-1155-contracts

## 1.5.0-gasless.2

### Patch Changes

- 0862fc8: Fix types reference for package export

## 1.5.0-gasless.1

### Patch Changes

- 4a67eee: Export preminter from package.json

## 1.5.0-gasless.0

### Minor Changes

- bb8069e: Adds first minter rewards to zora 1155 contracts.
- f3c86d8: Added deterministic contract creation from the Zora1155 factory
- 91db21c: Added the PremintExecutor contract, and updated erc1155 to support delegated minting

### Patch Changes

- bb8069e: Deprecate ZoraCreatorRedeemMinterStrategy at v1.0.1, a newer version will soon be released

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
