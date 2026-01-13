---
"@zoralabs/limit-orders": patch
---

Fix limit order payout handling for dual positive deltas. Previously, when limit order positions accumulated fees in both tokens (dual positive deltas), the payout would revert with a `CurrencyNotSettled` error because only one currency was withdrawn from the pool manager. The fix swaps the non-payout currency to the payout currency and pays out the combined amount, properly settling both deltas.
