---
"@zoralabs/limit-orders": patch
---

Fix limit order fulfillment to use correct currency when resolving payout paths

Limit order fulfillment now correctly consults the output currency's payout path configuration instead of the input currency's configuration. This ensures orders receive payouts based on the token being purchased rather than the token being sold, preventing potential currency mismatches when both tokens in a pair have different custom payout paths configured.
