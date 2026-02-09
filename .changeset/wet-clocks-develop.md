---
"@zoralabs/coins": patch
---

Fix swap fee distribution when price limits cause partial execution

When swapping large fee amounts, swaps can hit sqrtPriceLimit and only partially execute, leaving unsettled currency deltas. The hook now checks all currencies in the payout swap path (both the input currency and all intermediates) and takes/distributes any positive deltas as rewards. This ensures all collected fees are properly distributed even when swaps don't fully execute due to price constraints.
