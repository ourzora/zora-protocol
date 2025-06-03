---
"@zoralabs/coins": major
---

Upgraded coins to use Uniswap V4 with major breaking changes:

**New CoinV4 Implementation:**

- Migrated from Uniswap V3 to Uniswap V4 with advanced hook system
- Automatic LP fee collection and multi-hop reward distribution on every swap
- New `ZoraV4CoinHook` handles afterSwap operations for seamless reward processing
- Support for complex multi-position liquidity curves and discovery positions
- Multi-hop fee swapping through intermediate currencies (e.g., ContentCoin → BackingCoin → USDC)

**Factory Updates:**

- Updated `deploy()` function signature with new `poolConfig`, `message`, and `salt` parameters
- Automatic V3/V4 version selection based on pool configuration
- Deterministic coin deployment with salt support
- New `CoinCreatedV4` event for V4 coin deployments

**Reward System Changes:**

- Increased trade referral rewards from 10% to 15% (1500 basis points)
- Automatic reward distribution in unified backing currency (no manual withdrawal needed)
- Real-time fee conversion and payout on every trade

**New Interfaces and Events:**

- Added `IHasPoolKey` and `IHasSwapPath` interfaces for V4 functionality
- New `Swapped` event with detailed swap and price information
- New `CoinMarketRewardsV4` event for reward distribution tracking

**Breaking Changes:**

- Factory deploy function parameters changed significantly
- New pool configuration system replaces individual parameters
- V4 coins use different reward distribution mechanism than V3
