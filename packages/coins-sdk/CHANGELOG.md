# @zoralabs/coins-sdk

## 0.2.11

### Patch Changes

- a60f441b: Adding new getCoinSwaps and getCoinHolders endpoints

## 0.2.10

### Patch Changes

- Updated dependencies [262d1539]
  - @zoralabs/protocol-deployments@0.6.2

## 0.2.9

### Patch Changes

- 3c36f8ed: Small documentation and types fixes

## 0.2.8

### Patch Changes

- d8f29ef0: Fixed import paths

## 0.2.7

### Patch Changes

- bd371420: Small trade types fixes

## 0.2.6

### Patch Changes

- 86a3d4f3: Add tradeCoin function to trade creator and content coins

## 0.2.5

### Patch Changes

- 4153eddc: Added metadata uploading feature

## 0.2.4

### Patch Changes

- 3d5f9152: Removing `tradeCoin` function as its currently incompatible with UniswapV4 backed coins
- d8727949: Add create coin $ZORA initial buy

## 0.2.3

### Patch Changes

- Updated dependencies [9035ce3b]
  - @zoralabs/protocol-deployments@0.6.1

## 0.2.2

### Patch Changes

- Updated dependencies [73784d07]
- Updated dependencies [9adcb702]
- Updated dependencies [9adcb702]
  - @zoralabs/protocol-deployments@0.6.0

## 0.2.1

### Patch Changes

- aa2bc7cd: Add new backend queries to SDK

## 0.2.0

### Minor Changes

- 74885b84: Support creating uniswap v4 coins

## 0.1.3

### Patch Changes

- Updated dependencies [8cd56863]
  - @zoralabs/protocol-deployments@0.5.10

## 0.1.2

### Patch Changes

- Updated dependencies [73e95f69]
- Updated dependencies [0c50e8e7]
  - @zoralabs/protocol-deployments@0.5.6

## 0.1.1

### Patch Changes

- 9ed0ce76: - Publishing new coins hooks in `@zoralabs/protocol-deployments`
  - In coins, pulling ISwapRouter from `@zoralabs/shared-contracts`, and updated the shared interface to match the full interface of the ISwapRouter. This new interface is published in `@zoralabs/protocol-deployments`.
  - Removed publishing of the factory addresses directly in the wagmi config of the coins package, as that's inconsistent with the rest of the packages.
  - Updated the `@zoralabs/coins-sdk` to use `@zoralabs/protocol-deployments` for abis and addresses, which significantly reduces the dependency tree of it and has it follow the patterns of the other sdk packages.
- Updated dependencies [9ed0ce76]
- Updated dependencies [ce3022d8]
- Updated dependencies [ce3022d8]
- Updated dependencies [9ed0ce76]
- Updated dependencies [9ed0ce76]
  - @zoralabs/protocol-deployments@0.5.5

## 0.1.0

### Minor Changes

- 67356470: Updated to use new low market cap settings on ZORA.co

## 0.0.8

### Patch Changes

- Updated dependencies [265dcbeb]
  - @zoralabs/coins@0.7.1

## 0.0.7

### Patch Changes

- 529fe6f2: Fix coin create default value

## 0.0.6

### Patch Changes

- Updated dependencies [23f723dd]
  - @zoralabs/coins@0.7.0

## 0.0.5

### Patch Changes

- 514f8dd4: Added validation to URI used to create a coin matching a JSON object with URIs

## 0.0.4

### Patch Changes

- de700d12: Updated intermediary types in coins-sdk to better handle nulls
- b08b33ae: Fix multiple coins get and update types

## 0.0.3

### Patch Changes

- Updated dependencies [b9f717db]
  - @zoralabs/coins@0.6.1

## 0.0.2

### Patch Changes

- d9eb5a40: Initial release

## 0.0.2-sdkalpha.8

### Patch Changes

- Update export pattern for types on queries

## 0.0.2-sdkalpha.7

### Patch Changes

- 8f5d9185: Fix types and exports

## 0.0.2-sdkalpha.6

### Patch Changes

- Properly export set api key

## 0.0.2-sdkalpha.5

### Patch Changes

- Release API changes

## 0.0.2-sdkalpha.4

### Patch Changes

- d8cbf6ea: Update coin sdk structure and offchain functions

## 0.0.2-sdkalpha.3

### Patch Changes

- 60568036: Add offchain data

## 0.0.2-sdkalpha.2

### Patch Changes

- SDK Update

## 0.0.2-sdkalpha.1

### Patch Changes

- Fix package json inclusion

## 0.0.2-sdkalpha.0

### Patch Changes

- 29a34eaf: Introduce Coins SDK
- Updated dependencies [29a34eaf]
  - @zoralabs/coins@0.5.1-sdkalpha.0
