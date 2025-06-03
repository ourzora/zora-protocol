# @zoralabs/coins

## 1.0.0

### Major Changes

- 73e95f69: Upgraded coins to use Uniswap V4:

  **New CoinV4 Implementation:**

  - Migrated from Uniswap V3 to Uniswap V4, with logic moved into a hook.
  - Automatic LP fee collection and multi-hop reward distribution on every swap
  - New `ZoraV4CoinHook` handles afterSwap operations
  - Support for complex multi-position liquidity curves and discovery positions
  - Multi-hop fee swapping through intermediate currencies (e.g., ContentCoin → BackingCoin → Zora)

  **Factory Updates:**

  - Updated `deploy()` function signature with new `poolConfig`, `message`, and `salt` parameters
  - Automatic V3/V4 version selection based on pool configuration
  - Deterministic coin deployment with salt support
  - New `CoinCreatedV4` event for V4 coin deployments

  **Reward System Changes:**

  - Increased trade referral rewards from 10% to 15% (1500 basis points)
  - Automatic reward distribution in single backing currency

  **New Interfaces and Events:**

  - Added `IHasPoolKey` and `IHasSwapPath` interfaces for V4 functionality
  - New `Swapped` event with detailed swap and price information
  - New `CoinMarketRewardsV4` event for reward distribution tracking

  **Breaking Changes:**

  - New deterministic factory deploy function with salt

### Patch Changes

- 6b8bdd9d: Remove ability to create coin with legacy pool config

## 0.9.0

### Minor Changes

- 9ed0ce76: - Publishing new coins hooks in `@zoralabs/protocol-deployments`
  - In coins, pulling ISwapRouter from `@zoralabs/shared-contracts`, and updated the shared interface to match the full interface of the ISwapRouter. This new interface is published in `@zoralabs/protocol-deployments`.
  - Removed publishing of the factory addresses directly in the wagmi config of the coins package, as that's inconsistent with the rest of the packages.
  - Updated the `@zoralabs/coins-sdk` to use `@zoralabs/protocol-deployments` for abis and addresses, which significantly reduces the dependency tree of it and has it follow the patterns of the other sdk packages.
- 9ed0ce76: added deployWithHook to the coin factory

### Patch Changes

- 9ed0ce76: Refactored some reusable code into helper functions for the Coin factory

## 0.8.0

### Minor Changes

- 9ed0ce76: - Publishing new coins hooks in `@zoralabs/protocol-deployments`
  - In coins, pulling ISwapRouter from `@zoralabs/shared-contracts`, and updated the shared interface to match the full interface of the ISwapRouter. This new interface is published in `@zoralabs/protocol-deployments`.
  - Removed publishing of the factory addresses directly in the wagmi config of the coins package, as that's inconsistent with the rest of the packages.
  - Updated the `@zoralabs/coins-sdk` to use `@zoralabs/protocol-deployments` for abis and addresses, which significantly reduces the dependency tree of it and has it follow the patterns of the other sdk packages.
- 9ed0ce76: added deployWithHook to the coin factory

### Patch Changes

- 9ed0ce76: Refactored some reusable code into helper functions for the Coin factory

## 0.7.1

### Patch Changes

- 265dcbeb: Fixed factory address for wagmi

## 0.7.0

### Minor Changes

- 23f723dd: Integrate doppler for liquidity management with uniswap v3

## 0.7.0-doppler.0

### Minor Changes

- 96ab8907: Integrate doppler for liquidity management with uniswap v3

## 0.6.1

### Patch Changes

- b9f717db: Export IUniswapV3Pool interface

## 0.6.0

### Minor Changes

- 55bc4bf3: Update WETH tick and use as the minimum

## 0.5.0

### Minor Changes

- 39ffa77c: Add coin refunds for large sells with little liquidity

## 0.4.0

### Minor Changes

- e6ee19ce: Updated launch rewards - 10m coins for creator; remaining 990m for market

## 0.3.1

### Patch Changes

- 11854bbe: Updated factory impl abi to return coins purchased on deploy

## 0.3.0

### Minor Changes

- e1a3d68f: Refactored coin interface imports

## 0.2.0

### Minor Changes

- 9fa218c9: - Final events in preparation for V1 release
  - Updated the starting tick for WETH pools

## 0.1.1

### Patch Changes

- 1e10ac74: - Fixed coins package visibility
  - Renamed export to `coinFactory*`

## 0.1.0

### Minor Changes

- e42eb013: Initial setup
