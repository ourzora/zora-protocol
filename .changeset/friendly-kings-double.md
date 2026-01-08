---
"@zoralabs/coins": patch
---

Fix double-counting of fees in burnPositions during liquidity migration

Previously, the `burnPositions()` function was incorrectly adding `feesAccrued` to `callerDelta` when recording burned position amounts. Since `callerDelta` already includes accrued fees, this caused fees to be double-counted. This resulted in inflated token amounts being recorded in `BurnedPosition` structs, which could lead to `ERC20InsufficientBalance` errors when attempting to mint positions on a new hook during migration.

The fix:
- Use only `callerDelta` values directly without adding `feesAccrued`
- Add defensive balance checking in `mintPositions()` to cap liquidity at available token amounts
- Prevents migration failures from any remaining rounding discrepancies between burn and mint operations
