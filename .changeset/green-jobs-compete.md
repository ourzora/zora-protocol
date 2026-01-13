---
"@zoralabs/limit-orders": patch
---

Fix tick misalignment in minAway calculation

Align baseTick to tick spacing before calculating minAway in _tickForMultiple(). This prevents order creation from reverting when the current pool tick is not aligned to the pool's tick spacing.
