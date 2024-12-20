# @zoralabs/sparks-contracts

## 0.2.5

### Patch Changes

- 761238d6: Added base-sepolia and base deployments to sparks.

## 0.2.4

### Patch Changes

- c08ec3b3: Deployed SponsoredSparksSpender to more chains

## 0.2.3

### Patch Changes

- 7089746b: Added ETH sponsored sparks spender arguments.

## 0.2.2

### Patch Changes

- Updated dependencies [9b487789]
  - @zoralabs/shared-contracts@0.0.1

## 0.2.1

### Patch Changes

- 527aa518: Move from yarn to pnpm properly pinning deps packages

## 0.2.0

### Minor Changes

- 0ec838a4: Renamed Mints contracts to Sparks contracts. Removed all collect/collectPremint functions from the sparks manager contract

### Patch Changes

- 898c84a7: [chore] Update dependencies and runtime scripts

  This ensures jobs do not match binary names to make runs less ambigious and also that all deps are accounted for.

## 0.1.4

### Patch Changes

- 461d3ba2: collectPremint - fixed bug where paid mint value was being incorrectly sent to the premint call
- 60a8a7c4: collectPremint - firstMinter is explicitly specified in call

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
