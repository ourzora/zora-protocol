---
"@zoralabs/coins-sdk": minor
---

Add `getTrend` and `getTrends` for looking up trend coins

- `getTrend({ ticker })` — look up a single trend coin by ticker (case-insensitive, server-side)
- `getTrends({ name })` — search trend coins by name with pagination
- Also exports `TrendCoinResponse` and `TrendsByNameResponse` types for consumers
