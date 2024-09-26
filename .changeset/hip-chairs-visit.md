---
"@zoralabs/protocol-sdk": patch
---

For the functions `getToken` and `getTokensOfContract`, the returned `MintableReturn` type has been updated to provide more information about the primary mint status:

- Added `primaryMintActive` boolean to indicate if the primary mint is currently active.
- Added `primaryMintEnd` optional `bigint` to show the end time of the primary mint, if applicable.
- Added `secondaryMarketActive` boolean to indicate if the secondary market is currently active.
- Modified `prepareMint` to be conditionally available:
  - When `primaryMintActive` is `true`, `prepareMint` is available as a `PrepareMint` function.
  - When `primaryMintActive` is `false`, `prepareMint` is set to `undefined`.

This allows for developers to know if the primary mint is active or not, and if not, if they should buy on secondary.
