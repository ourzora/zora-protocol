# @zoralabs/cli

## 1.1.0

### Minor Changes

- 3c9885c30: Add trade activity (buys and sells) to profile
  - New `profile trades` subcommand with paginated view of buy/sell history
  - Add Trades tab to the default `profile` command alongside Posts and Holdings
  - Add Address column to profile posts view

- 92c19fa41: Add paginated `profile posts` and `profile holdings` subcommands
  - `zora profile posts [identifier]` — browse a profile's created coins with cursor-based pagination
  - `zora profile holdings [identifier]` — browse a profile's coin holdings with pagination and sorting (`--sort usd-value|balance|market-cap|price-change`)
  - Both subcommands support `--limit`, `--after`, `--live`, `--static`, `--refresh`, and `--json` flags

- 513c9116d: Add `get holders` subcommand to show top holders of a coin with balance and % of total supply
  - Supports `--json`, `--live` (interactive with pagination), and `--static` output modes
  - Adds a Holders tab to the `zora get` live view alongside Price History
  - Supports `--limit` (1-20, default 10), `--after` cursor pagination, and type prefix arguments

- 1cf0e33eb: Add tabbed live view to `zora get` and move `price-history` under it
  - `zora get <address-or-name>` now shows an interactive live view with a pinned coin summary and tabbed detail panels (Price History), matching the `zora profile` interaction pattern
  - `zora get price-history <address-or-name>` replaces the standalone `zora price-history` command
  - Ambiguous coin names (matching both a creator-coin and a trend) now error with a suggestion to specify the type, instead of showing both results

- 4cb422030: Add `zora get trades <coin>` subcommand showing recent buy/sell activity on a coin
  - New `get trades` subcommand with `--live`, `--static`, and `--json` output modes, cursor-based pagination (`--limit`, `--after`), and auto-refresh support
  - Add Trades tab to the main `zora get` live view alongside Price History, switchable with arrow keys or number keys
  - JSON output of `zora get` now includes a `trades` array with recent swap activity

### Patch Changes

- 24c4a7c42: Decode Solidity revert errors into friendly trade messages
  - Replace opaque "Execution reverted" messages with actionable guidance for 17 known contract errors
  - Fix RPC transport to preserve JSON-RPC error code/data for proper viem error classification

- 366b21a32: Auto-detect coin type on sell when only one is held
  - When both a creator-coin and trend share the same name, the sell command now checks the user's balance and auto-selects the one they hold
  - If the user holds both or neither, the existing disambiguation error is shown

- aedd01578: `zora balance` and `zora balance coins` updates:
  - Add Type column showing coin type (post, creator-coin, trend) in table and JSON output
  - Add truncated Address column
  - Remove Symbol column
  - Add arrow key row selection and Enter/c to copy coin address in live mode

  Balance and explore shared improvements:
  - Post coins without names now show truncated address as name

- b58d57e92: Add arrow key navigation and Enter to copy address in explore command
- e59f7958d: Use SDK valuation for more accurate coin balance USD values when an API key is configured
  - Prefer `valuation.marketValueUsd` from the SDK when available, fall back to `balance × priceInUsdc`
  - Show informational banner when no API key is configured

- 36657cdee: Show PATH configuration instructions after global install when npm bin directory is not in PATH
- Updated dependencies [8baf100b2]
- Updated dependencies [bcfc04153]
  - @zoralabs/coins-sdk@0.6.0

## 1.0.1

### Patch Changes

- Update CLI README documentation and feedback links
  - Point documentation link to cli.zora.com
  - Update feedback contacts to x.com/zorasupport and support.zora.co

## 1.0.0

### Major Changes

- 7d6785e3d: Official ZORA CLI Beta Release

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
