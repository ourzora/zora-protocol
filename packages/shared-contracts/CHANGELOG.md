# @zoralabs/shared-contracts

## 0.0.5

### Patch Changes

- 9adcb702: Added uniswap QuoterV2 to protocol-deployments

## 0.0.4

### Patch Changes

- 67b84355: Publish shared-contracts
- bc366e3e: Reading chain configs from node_modules folder

## 0.0.3

### Patch Changes

- 9ed0ce76: - Publishing new coins hooks in `@zoralabs/protocol-deployments`
  - In coins, pulling ISwapRouter from `@zoralabs/shared-contracts`, and updated the shared interface to match the full interface of the ISwapRouter. This new interface is published in `@zoralabs/protocol-deployments`.
  - Removed publishing of the factory addresses directly in the wagmi config of the coins package, as that's inconsistent with the rest of the packages.
  - Updated the `@zoralabs/coins-sdk` to use `@zoralabs/protocol-deployments` for abis and addresses, which significantly reduces the dependency tree of it and has it follow the patterns of the other sdk packages.

## 0.0.2

### Patch Changes

- 23f723dd: Integrate doppler for liquidity management with uniswap v3

## 0.0.2-doppler.0

### Patch Changes

- 96ab8907: Integrate doppler for liquidity management with uniswap v3

## 0.0.1

### Patch Changes

- 9b487789: Release zora shared-contracts package
