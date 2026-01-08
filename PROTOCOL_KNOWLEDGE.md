# Protocol Knowledge Base

This file contains institutional knowledge about protocol integrations, non-obvious behaviors, and lessons learned from development. AI agents should reference this when writing or reviewing protocol code, and should add new entries when discovering nuances.

## How to Use This File

**When writing protocol code:** Review relevant sections before implementation.
**When fixing bugs:** If the fix involves a non-obvious protocol behavior, add an entry.
**When reviewing code:** Check if the code respects known nuances in this file.

---

## Uniswap V4

### ModifyLiquidity Return Values

**The Issue:** `modifyLiquidity()` returns `callerDelta` that already includes accrued fees; `feesAccrued` is informational only.

**The Interface:**

```solidity
/// @notice Modify the liquidity for the given pool
/// @dev Poke by calling with a zero liquidityDelta
/// @param key The pool to modify liquidity in
/// @param params The parameters for modifying the liquidity
/// @param hookData The data to pass through to the add/removeLiquidity hooks
/// @return callerDelta The balance delta of the caller of modifyLiquidity. This is the total of both principal delta and feesAccrued
/// @return feesAccrued The balance delta of the fees generated in the liquidity range. Returned for informational purposes
function modifyLiquidity(
  PoolKey memory key,
  IPoolManager.ModifyLiquidityParams memory params,
  bytes calldata hookData
) external returns (BalanceDelta callerDelta, BalanceDelta feesAccrued);
```

**Wrong:**

```solidity
(BalanceDelta liquidityDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(...);
uint128 totalReceived = uint128(liquidityDelta.amount0() + feesAccrued.amount0()); // Double-counting!
```

**Correct:**

```solidity
(BalanceDelta callerDelta, ) = poolManager.modifyLiquidity(...);
uint128 totalReceived = uint128(callerDelta.amount0()); // callerDelta already includes fees
```

**Reference:** [Uniswap V4 IPoolManager Interface](https://github.com/Uniswap/v4-core/blob/main/src/interfaces/IPoolManager.sol)

---

## Solidity Patterns

_(Add entries as discovered)_

---

## Zora-Specific Patterns

_(Add entries as discovered)_

---

## Entry Template

When adding new entries, use this format:

```markdown
### Brief Title

**The Issue:** One-sentence description of the non-obvious behavior.

**Wrong:**

\`\`\`solidity
// Code that demonstrates the mistake
\`\`\`

**Correct:**

\`\`\`solidity
// Code that demonstrates the fix
\`\`\`

**Reference:** Link to documentation or source code (if applicable)
```
