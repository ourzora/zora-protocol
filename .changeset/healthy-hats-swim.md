---
"@zoralabs/coins-contracts": patch
---

Consolidate constants into single CoinConstants.sol file

- Consolidated constants from MarketConstants.sol, CreatorCoinConstants.sol, and CoinRewardsV4.sol into CoinConstants.sol
- Removed duplicate constant files to improve code organization
- Updated all imports across the codebase to use the unified constants file
- Renamed CURRENCY to CREATOR_COIN_CURRENCY for better clarity
- Removed unused MIN_ORDER_SIZE constant

This is an internal refactoring that improves code maintainability without changing any public APIs or contract behavior.