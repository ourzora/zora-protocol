# @zoralabs/mints-contracts

## 0.1.3

### Patch Changes

- 8e514b7: Removed reentrancy guard from `MintsEthUnwrapperAndCaller`

## 0.1.2

### Patch Changes

- b6fc3a4: When updating token uris in the mints manager, it notifies the Zora Mints 1155 to emit an event for all token ids that were updated

## 0.1.1

### Patch Changes

- 4b22aa9: Clear out transferred mints state on the mints manager to save gas

## 0.1.0

### Minor Changes

- 50a4e09: - 1155 contracts use the MINTs contracts to get the mint fee, mint, and redeem a mint ticket upon minting.
  - `ZoraCreator1155Impl` adds a new method `mintWithMints` that allows for minting with MINTs that are already owned.

### Patch Changes

- 50a4e09: - To support the MINTs contract passing the first minter as an argument to `premintV2WithSignerContract` - we add the field `firstMinter` to `premintV2WithSignerContract`, and then in the 1155 check that the firstMinter argument is not address(0) since it now can be passed in manually.
