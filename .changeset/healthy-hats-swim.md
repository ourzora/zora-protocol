---
"@zoralabs/coins": patch
---

Consolidate and clarify coin constants

- Renamed `CREATOR_LAUNCH_REWARD` to `CONTENT_COIN_INITIAL_CREATOR_SUPPLY` for clarity
- Renamed `CREATOR_VESTING_SUPPLY` to `CREATOR_COIN_CREATOR_VESTING_SUPPLY` for consistency
- Removed redundant `POOL_LAUNCH_SUPPLY` constant (use `CONTENT_COIN_MARKET_SUPPLY` instead)
- Changed library constants from `public` to `internal` 
- Made supply constants derived from calculations to show relationships clearly