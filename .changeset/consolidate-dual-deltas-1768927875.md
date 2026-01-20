---
"@zoralabs/limit-orders": patch
---

Fix dual positive deltas consolidation in burnAndRefund

- Consolidate payouts to single currency when burning limit orders with dual positive deltas
- Extract path-building logic into reusable `_buildSingleHopPath` helper function
- Ensure users receive proceeds in their original deposit currency by swapping counter-assets
- Align burnAndRefund behavior with burnAndPayout for consistent payout consolidation