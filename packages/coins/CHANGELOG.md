# @zoralabs/coins

## 2.2.1

### Patch Changes

- 7ec6134b: Flatten hooks into single hook implementation

  Consolidates multiple hook contracts into a single unified hook for simplified architecture and better maintainability.

- ae9424ab: Ignore collecting from liquidity positions with empty fee growth

## 2.2.0

### Minor Changes

- adf98059: Adds platform referral and trade referral functionality to creator coins, and unifies the fee structure between content and creator coins with a simplified 1% total fee.

  ## New Features:

  - Platform referral and trade referral functionality for creator coins (previously only supported on content coins)
  - Unified fee structure: Both content and creator coins use identical 1% fee distribution

  ### Fee Changes - Content Coins

  | Recipient         | Before (3% total fee) | After (1% total fee) |
  | ----------------- | --------------------- | -------------------- |
  |                   | % of Fee        | % of Fee |
  | Creator           | 33.33%                | 50%                  |
  | Platform Referral | 10%                   | 20%                  |
  | Trade Referral    | 10%                   | 4%                   |
  | Doppler           | 3.33%                 | 1%                   |
  | Protocol          | 10%                   | 5%                   |
  | LP Rewards        | 33.33%                | 20%                  |

  ### Fee Changes - Creator Coins

  | Recipient         | Before (3% total fee) | After (1% total fee) |
  | ----------------- | --------------------- | -------------------- |
  |                   | % of Fee        | % of Fee |
  | Creator           | 33.33%                | 50%                  |
  | Platform Referral | -                     | 20%                  |
  | Trade Referral    | -                     | 4%                   |
  | Doppler           | -                     | 1%                   |
  | Protocol          | 33.33%                | 5%                   |
  | LP Rewards        | 33.33%                | 20%                  |

  **Implementation Changes:**

  - Consolidated reward logic into `CoinRewardsV4.distributeMarketRewards()`

  **Backwards Compatibility:**

  - Existing `CreatorCoinRewards` event is still emitted for backwards compatibility when rewards are distributed for a CreatorCoin
  - Additionally, when market rewards are distributed for a CreatorCoin, the same `CoinMarketRewardsV4` event that is already emitted for ContentCoins is now also emitted

## 2.1.2

### Patch Changes

- 8b85ab94: Removed some unused constants

## 2.1.1

### Patch Changes

- 498e5c9d: Consolidated POOL_LAUNCH_SUPPLY into a single constant

## 2.1.0

### Minor Changes

- dac72691: Remove Uniswap V3 support and refactor coin architecture

  **Removal of V3 Support:**

  - Removed support for creating coins based on Uniswap V3 - only V4 coins are supported
  - Default coin deployment now creates Uniswap V4 coins when no config is provided (previously created V3)
  - Removed V3-specific test files and utilities
  - Updated remaining tests to use V4 deployment methods
  - Removed V3 configuration functions and encoders
  - Added revert logic for V3 deployment attempts in factory deploy functions

  **Architecture Refactoring:**

  - Merged BaseCoinV4 functionality into BaseCoin.sol to consolidate Uniswap V4 integration
  - Combined ICoinV4 interface with ICoin interface to simplify the interface hierarchy
  - Updated ContentCoin and CreatorCoin to inherit directly from BaseCoin
  - Removed duplicate files: BaseCoinV4.sol and ICoinV4.sol
  - Updated all imports and references throughout the codebase
  - This is an internal refactoring that doesn't change external functionality

### Patch Changes

- deb9175b: Enforce 32 bytes for decoding trade referral address from hook data

## 2.0.0

### Major Changes

- acb9ff94: Move ZoraFactoryImpl to 2-step ownable with same storage slots

  This change updates the factory contract to use Ownable2StepUpgradeable instead of OwnableUpgradeable. The change maintains storage slot compatibility while adding the two-step ownership transfer pattern for enhanced security.

  Key changes:

  - ZoraFactoryImpl now inherits from Ownable2StepUpgradeable
  - Adds pendingOwner() function
  - Requires acceptOwnership() call to complete ownership transfers
  - Maintains storage slot compatibility for upgrades

### Patch Changes

- 65d36dbb: Refactor coinv4 into basecoinv4 and content coin

  This refactoring splits the coinv4 implementation into a base coin contract and content coin contract for better modularity and separation of concerns.

## 1.1.2

### Patch Changes

- 522a7c33: Update LICENSE for coins
- 5c561b01: Fixed bug where hooks could not receive taken eth for paying out rewards

## 1.1.1

### Patch Changes

- 604cd3ab: When migrating liquidity to a new hook, dont execute any after swap logic in the original hook
- 588da84e: Fix market supply calculation
- f6300031: Added ability for hooks to have liquidity be migrated to

## 1.1.0

### Minor Changes

- 73784d07: Added creator coins, contracts and hooks, enabling creator coins with vesting to be created.

### Patch Changes

- 3d5e77fe: Coin name and symbol can be updated by an owner
- 9adcb702: Added the AutoSwapper contract
- 52edc9d5: Don't auto-withdraw vested creator coins on every swap
- 73784d07: A coins initial liquidity can be migrated from one hook to the next, given that the upgrade path is approved

## 1.0.1

### Patch Changes

- 8cd56863: BuySupplyWithSwapRouterHook supports v4 coins

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
