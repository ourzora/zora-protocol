---
"@zoralabs/limit-orders": patch
---

Fix multi-hop payout path for content coin limit orders

- Pass `coinIn` instead of `coinOut` to `burnAndPayout` in `LimitOrderFill._fillOrder`
- This ensures content coin orders pay out in the ultimate backing currency (ZORA) via the multi-hop path
- Previously, content coin orders would fall back to single-hop and pay out in creator coin instead of ZORA
