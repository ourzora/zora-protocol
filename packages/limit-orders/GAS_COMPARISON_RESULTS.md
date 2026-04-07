# Gas Comparison Results: Current Swaps vs Swaps w/ Internal Swap Detection

**Date:** 2025-12-01
**Branches Compared:**
- **Baseline (Branch 1):** `rohan/gas-benchmarking` - Gas benchmarking infrastructure without optimization
- **Optimized (Branch 2):** `rohan/internal-swap-optimization` - With `_isInternalSwap` hook optimization

## Terminology: Understanding "Hops"

The term "hops" appears in two different contexts in these benchmarks:

### Payout Conversion Hops (Backend Fill Operations)

When the backend calls `limitOrderBook.fill()` to execute orders, **"hops"** refers to how order payouts are converted:

**0/1 Payout-Hop (Direct)**
- Order fill pays out directly in the desired currency without conversion
- Example: Order on creatorCoin pool → payout in ZORA (other side of the pair)
- Minimal internal swaps for payout

**2 Payout-Hops (Conversion Required)**
- Order fill requires payout conversion through intermediate pools
- Example: Order on contentCoin pool → payout path: contentCoin → creatorCoin → ZORA
- Each conversion hop triggers hook execution (where our optimization saves gas!)

### User Swap Routing + Payout Conversion (User Autofill Operations)

When users initiate swaps that cross limit orders, there are **TWO sources of internal swaps**:

1. **User's multi-hop routing**: The path users take to reach the pool (e.g., ZORA → creator → content)
2. **Order payout conversion**: Internal swaps to convert filled order payouts back to desired currency

Both routing hops and payout conversion hops trigger the hook, so the optimization provides compounding gas savings. The "User Swap + Autofill Operations" tests measure the total gas including both types of internal swaps.

## Executive Summary

The `_isInternalSwap` optimization provides **18-62% gas savings** across all test scenarios by detecting internal/recursive swaps and skipping unnecessary fee collection logic in the ZoraV4CoinHook.

## Detailed Comparison

### Backend Fill Operations

Backend services call `limitOrderBook.fill()` to execute existing limit orders. These tests measure the gas cost of filling N orders in a single transaction.

| Orders Filled | Baseline Gas | Optimized Gas | Gas Saved | % Improvement |
|---------------|--------------|---------------|-----------|---------------|
| 1 order (0/1 payout-hop) | 3,982,669 | 3,260,509 | 722,160 | 18.1% |
| 1 order (2 payout-hops) | 7,496,038 | 6,144,078 | 1,351,960 | 18.0% |
| 5 orders (2 payout-hops) | 11,682,458 | 7,792,758 | 3,889,700 | 33.3% |
| 10 orders (2 payout-hops) | 13,940,712 | 9,872,756 | 4,067,956 | 29.2% |
| 50 orders | 59,311,104 | 26,598,104 | 32,713,000 | 55.2% |
| 100 orders | 111,074,619 | 47,656,019 | 63,418,600 | 57.1% |
| 150 orders | 164,396,574 | 68,957,450 | 95,439,124 | 58.1% |

### User Swap + Autofill Operations

Users initiate swaps that automatically trigger order fills as a side effect. These tests measure the total gas cost when a user swap crosses multiple orders.

| Orders Filled | Baseline Gas | Optimized Gas | Gas Saved | % Improvement |
|---------------|--------------|---------------|-----------|---------------|
| 10 orders | 15,204,181 | 8,700,941 | 6,503,240 | 42.8% |
| 25 orders | 25,052,062 | 14,201,062 | 10,851,000 | 43.3% |
| 40 orders | 34,638,545 | 19,625,345 | 15,013,200 | 43.4% |
| 50 orders | 40,982,404 | 23,168,604 | 17,813,800 | 43.5% |
| 75 orders | 60,183,892 | 32,899,292 | 27,284,600 | 45.3% |
| 100 orders | 112,356,369 | 42,545,248 | 69,811,121 | 62.1% |

### Specialized Scenarios

| Test Scenario | Baseline Gas | Optimized Gas | Gas Saved | % Improvement |
|--------------|--------------|---------------|-----------|---------------|
| Empty fill | 209,668 | 143,268 | 66,400 | 31.7% |
| Large swap w/ fee conversion | 2,454,346 | 2,008,446 | 445,900 | 18.2% |
| Max fillcount (25) | 22,842,877 | 16,128,877 | 6,714,000 | 29.4% |
| Mixed sizes | 11,682,945 | 7,793,945 | 3,889,000 | 33.3% |
| Same tick | 11,103,207 | 7,444,207 | 3,659,000 | 33.0% |
| User swap 1-hop autofill (40) | 23,377,551 | 16,707,751 | 6,669,800 | 28.5% |
| User swap 1-hop autofill (50) | 29,066,384 | 20,375,584 | 8,690,800 | 29.9% |

## Key Insights

### Optimization Impact by Scale

1. **Small Backend Fills (18-33% savings)**
   - Single order fills: 18% improvements
   - 5-order batches: 33% savings
   - 10-order batches: 29% savings

2. **Medium Scale (43-55% savings)**
   - User autofill operations (10-75 orders): consistently save 43-45%
   - Backend fills (50 orders): achieve 55% savings

3. **Large Scale (57-62% savings)**
   - 100-order user swaps: 62.1% improvement (69.8M gas saved!)
   - 100-order backend fills: 57.1% improvement (63.4M gas saved)
   - 150-order backend fills: 58.1% improvement (95.4M gas saved)

### Why

The optimization becomes more impactful at scale because:
- Each order triggers multiple internal swaps for fee conversions
- The baseline performs full fee collection logic for every internal swap
- The optimization skips all this logic, multiplying savings across orders
- At 100+ orders, the cumulative effect is massive (60-62% reduction)

### Technical Implementation

The optimization adds `_isInternalSwap()` detection to ZoraV4CoinHook:

```solidity
function _isInternalSwap(address sender) internal view returns (bool) {
    return sender == address(this) ||
           sender == address(zoraLimitOrderBook) ||
           zoraHookRegistry.isRegisteredHook(sender);
}
```

Early returns in `_beforeSwap()` and `_afterSwap()` when internal swaps are detected:

```solidity
function _beforeSwap(...) internal virtual override returns (...) {
    if (_isInternalSwap(sender)) {
        return (BaseHook.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }
    // ... rest of fee collection logic
}
```

## Cost Impact Examples

Using 100-order user swap scenario (69.8M gas saved) at $3,000/ETH:

| Base Fee | Baseline Cost | Optimized Cost | $ Saved |
|----------|---------------|----------------|---------|
| 0.0001 gwei (100,000 wei) | $0.0337 | $0.0128 | $0.0209 |
| 0.001 gwei (1,000,000 wei) | $0.337 | $0.128 | $0.209 |
| 0.01 gwei (10,000,000 wei) | $3.37 | $1.28 | $2.09 |

## Conclusion

The `_isInternalSwap` optimization provides substantial gas savings across all scenarios, with the largest impact on high-volume operations. The 18-62% improvement range makes this optimization critical for production deployment, especially for backend fill operations and user-facing autofill scenarios.

**Recommendation:** Merge this optimization into production immediately. The gas savings are significant and the implementation is clean with no breaking changes to external interfaces.


## Latest Benchmarks (current branch, rerun 2025-12-01)

### LimitOrderSwapGas (fork @ block 38,875,958; production router)
| Scenario | Gas |
| --- | --- |
| Hop1 (ZORA → creator) fill5 | **4,204,840** |
| Hop1 fill10 | **4,671,165** |
| Hop1 fill25 | **6,008,081** |
| Hop1 fill50 | **8,317,174** |
| Hop2 (ZORA → creator → content) fill5 | **7,062,539** |
| Hop2 fill10 | **7,688,068** |
| Hop2 fill25 | **9,569,256** |
| Hop2 fill50 | **12,684,187** |
| Hop3 (USDC → ZORA → creator) fill0 | **5,504,247** |
| Hop3 fill5 | **9,673,686** |
| Hop3 fill10 | **10,299,041** |
| Hop3 fill25 | **12,179,705** |
| Hop3 fill50 | **15,293,763** |
| Hop4 (WETH → USDC → ZORA → creator) fill0 | **5,625,730** |
| Hop4 fill5 | **9,977,871** |
| Hop4 fill10 | **10,603,389** |
| Hop4 fill25 | **12,484,542** |
| Hop4 fill50 | **15,599,414** |

### LimitOrderFillGas (local/anvil)
| Scenario | Gas |
| --- | --- |
| Baseline swap (no orders) | **1,696,598** |
| Single order (direct payout) | **133,925** |
| Single order (multihop payout) | **166,591** |
| Five orders (multihop payout) | **567,240** |
| Ten orders (multihop payout) | **1,068,298** |
| Empty fill | **79,723** |
| Large swap w/ fee conversion | **1,925,776** |
| Max fillcount (25 orders) | **2,575,596** |
| User swap autofill 10 orders | **5,899,189** |
| User swap autofill 25 orders | **8,036,447** |
| User swap autofill 40 orders | **10,066,795** |
| User swap autofill 50 orders | **11,369,269** |
| User swap autofill 75 orders | **14,684,719** |
| User swap autofill 100 orders | **17,868,828** |
| User swap autofill 1-hop 40 orders | **5,758,247** |
| User swap autofill 1-hop 50 orders | **6,685,848** |
| User swap w/ autofill (multihop) | **5,094,889** |
| Backend fill 50 orders | **5,096,006** |
| Backend fill 100 orders | **10,171,297** |
| Backend fill 150 orders | **15,299,656** |
| Mixed sizes | **566,754** |
| Same tick | **549,968** |
