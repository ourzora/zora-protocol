# @zoralabs/cli

## 0.3.1

### Patch Changes

- Updated dependencies [278d7705e]
- Updated dependencies [b41ed41f9]
  - @zoralabs/coins-sdk@0.5.2

## 0.3.0

### Minor Changes

- acfd23ec0: Add `profile` command to view a wallet's posts and holdings
  - `zora profile [address]` displays created coins and coin balances for any wallet or profile handle
  - Supports table, json, and live output modes
  - Live mode renders switchable tabs (Posts / Holdings) with keyboard navigation and auto-refresh
  - Defaults to the user's configured wallet when no identifier is provided

### Patch Changes

- 150043e81: Truncate coin addresses in explore table to prevent line wrapping and column bleed

## 0.2.4

### Patch Changes

- cde9a14b5: - Add live data refresh with unified --output flag
  - Add valueUsd, swapCoinType, transactionHash, logIndex to PostHog swap events
  - Fix buy/sell commands to respect global --json flag
  - Include USD value in PostHog swap events
  - Use compact short notation for large balances
  - Add price-history command
  - Add responsive tables and interactive explore with live pagination
  - Consolidate formatting utils and remove duplication
  - Use spendableBalance for sub-100% --percent buy calculations
  - Add beta warning banner to CLI output

## 0.2.3

### Patch Changes

- 32daf194: Fix npm publish to include dist/ build output

## 0.2.2

### Patch Changes

- 78df4fc6: Minor debugging trade release
- Updated dependencies [78df4fc6]
  - @zoralabs/coins-sdk@0.5.1

## 0.2.1

### Patch Changes

- Updated dependencies [e174b53f]
  - @zoralabs/coins-sdk@0.5.0

## 0.2.0

### Patch Changes

- 01584e8b: Release the CLI prerelease only

## 0.2.0-cli-dev.0

### Minor Changes

- 1fb88dd4: Release new cli package
