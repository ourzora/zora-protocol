# Protocol Knowledge Base

This file contains institutional knowledge about protocol integrations, non-obvious behaviors, and lessons learned from development. AI agents should reference this when writing or reviewing protocol code, and should add new entries when discovering nuances.

## How to Use This File

**When writing protocol code:** Review relevant sections before implementation.
**When fixing bugs:** If the fix involves a non-obvious protocol behavior, add an entry.
**When reviewing code:** Check if the code respects known nuances in this file.

---

## Uniswap V4

### Pool Manager Sync Before Settle

**The Issue:** Pool manager must be synced before settling currencies to ensure accurate balance tracking and prevent DoS attacks.

**Wrong:**

```solidity
// For native ETH - missing sync
poolManager.settle{value: amount}();

// For ERC20 - missing sync  
currency.transfer(address(poolManager), amount);
poolManager.settle();
```

**Correct:**

```solidity
// For native ETH - sync first
poolManager.sync(currency);
poolManager.settle{value: amount}();

// For ERC20 - sync first
poolManager.sync(currency);
currency.transfer(address(poolManager), amount);
poolManager.settle();
```

**Why:** Without syncing, the pool manager's internal accounting may not reflect the actual balance, leading to settlement failures or DoS conditions. This is especially critical for native ETH where the value is transferred as part of the settle call. The `sync()` call updates the pool manager's cached balance to match the actual contract balance before settlement occurs.

**Reference:** [Zora Audit Issue #9 - Unsynced ETH settlement can result in DoS](https://github.com/kadenzipfel/zora-autosell-audit/issues/9)

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

### Hash Function Security with Dynamic Data

**The Issue:** `abi.encodePacked` can create hash collisions when concatenating dynamic-length data or multiple parameters without padding.

**Wrong:**

```solidity
bytes32 id = keccak256(abi.encodePacked(poolKey, coin, tick, maker, nonce));
```

**Correct:**

```solidity  
bytes32 id = keccak256(abi.encode(poolKey, coin, tick, maker, nonce));
```

**Why:** `abi.encodePacked` concatenates values without padding, which can lead to ambiguous encodings. For example, `abi.encodePacked("aa", "b")` produces the same result as `abi.encodePacked("a", "ab")`. `abi.encode` provides proper 32-byte padding between parameters, eliminating this collision risk.

**Performance Impact:** `abi.encode` has slightly higher gas cost (~50-100 gas), but the security benefit far outweighs the minimal cost difference.

**Reference:** [Solidity Documentation on ABI Encoding](https://docs.soliditylang.org/en/latest/abi-spec.html)

---

## Zora-Specific Patterns

### Safe Typecasting from Uniswap V4 BalanceDelta

**The Issue:** Uniswap V4's BalanceDelta returns int128 values that need to be cast to unsigned types, but the casting must respect the sign semantics to avoid overflow vulnerabilities.

**Wrong:**

```solidity
(BalanceDelta delta, ) = poolManager.modifyLiquidity(...);
int128 amount0 = delta.amount0();
uint128 payout = uint128(amount0); // Dangerous! Could overflow if amount0 is negative
```

**Correct:**

```solidity
(BalanceDelta delta, ) = poolManager.modifyLiquidity(...);
int128 amount0 = delta.amount0();
uint128 payout;

if (amount0 > 0) {
    // Safe cast when value is known to be positive
    payout = uint128(amount0);
} else if (amount0 < 0) {
    // Safe cast when converting negative to positive amount owed
    payout = uint128(uint256(int256(-amount0)));
}
```

**Why:** BalanceDelta amounts can be negative (owed to pool) or positive (owed from pool). Direct casting from int128 to uint128 when the value is negative will cause an overflow. The double cast through int256 and uint256 when negating ensures the value fits within uint128 bounds.

**Common Patterns:**
- Positive amounts from burning liquidity: `uint128(positiveAmount)`
- Negative amounts when minting liquidity: `uint128(uint256(int256(-negativeAmount)))`
- Settlement deltas: `uint256(-negativeAmount)` for amounts owed to pool

**Reference:** packages/limit-orders/src/libs/ - LimitOrderCreate.sol:238-244, LimitOrderLiquidity.sol:99-110, SwapLimitOrders.sol:134-137

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
