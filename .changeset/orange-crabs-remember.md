---
"@zoralabs/cli": patch
---

Use SDK valuation for more accurate coin balance USD values when an API key is configured

- Prefer `valuation.marketValueUsd` from the SDK when available, fall back to `balance × priceInUsdc`
- Show informational banner when no API key is configured
