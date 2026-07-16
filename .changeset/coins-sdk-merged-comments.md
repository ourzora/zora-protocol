---
"@zoralabs/coins-sdk": minor
---

Add `getCoinMergedComments` for a coin's unified comment feed. It returns on-chain, backfilled, and off-chain comments pre-sorted newest-first under a single cursor — mirroring the `GraphQLMergedComment` union the Zora web and mobile apps consume. The existing `getCoinComments` is unchanged (on-chain `zoraComments` only).
