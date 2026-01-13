---
"@zoralabs/limit-orders": patch
---

Improve payout swap path validation in limit order fulfillment. The `_resolvePayoutPath` function now validates that multi-hop swap paths from coins have their first hop matching the expected payout currency. If validation fails, the system automatically falls back to constructing a simple single-hop path, ensuring correct payouts regardless of the coin's swap path configuration.
