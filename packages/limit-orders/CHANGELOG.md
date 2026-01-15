# @zoralabs/limit-orders

## 0.2.1

### Patch Changes

- dd012477: Add swap price data fields to SwapWithLimitOrdersExecuted event. The event now includes actual swap amounts (amount0 and amount1) and final sqrt price (sqrtPriceX96), while removing the redundant delta field. This breaking change provides more detailed swap information for indexers and frontends to track swaps with limit orders without requiring additional RPC calls.
- 517d3f74: Fix security vulnerability that allowed withdrawal of fillable limit orders. When a limit order becomes fillable due to market price crossing the limit price, users are now prevented from withdrawing the order and must execute it instead. This enforces proper market behavior and prevents users from backing out of orders that should be filled based on current market conditions.
- 0b183d5e: Improve payout swap path validation in limit order fulfillment. The `_resolvePayoutPath` function now validates that multi-hop swap paths from coins have their first hop matching the expected payout currency. If validation fails, the system automatically falls back to constructing a simple single-hop path, ensuring correct payouts regardless of the coin's swap path configuration.
- e84a6902: Fix CEI violation in limit order filling by moving order removal before external liquidity calls to prevent potential reentrancy issues
- 17bf2b5e: Fix limit order fill direction to derive from actual tick movement

  Fixed limit order filling in `ZoraV4CoinHook` by deriving the fill direction from actual tick movement instead of using the swap direction parameter. The hook now only attempts to fill limit orders when there's an actual tick change, and determines the currency direction based on the comparison between before and after swap ticks. This ensures orders are filled correctly regardless of swap direction.

- 928b4f65: Fix limit order execution logic for correct tick queue placement

  Fixed critical bug where limit orders were being enqueued at incorrect ticks, preventing proper execution. Currency0 orders now correctly execute when price rises to the upper tick, and Currency1 orders execute when price falls to the lower tick.

- 3d0bb73c: Fix router-based limit order fills to use correct currency direction

  Fixed bug in SwapWithLimitOrders where router fallback incorrectly inverted the currency direction parameter when calling `_fillOrders`. This caused orders to be skipped when the hook doesn't support limit order fills. The router now correctly passes `isCoinCurrency0` instead of `!isCoinCurrency0`, ensuring fills occur in the proper direction.

- a61e0250: Remove duplicate validateOrderInputs call in handleCreateCallback

  Eliminates redundant validation that was occurring in both \_prepareCreateData and handleCreateCallback functions, reducing gas costs while maintaining input validation security.

- 14f1314a: Fix tick misalignment in minAway calculation

  Align baseTick to tick spacing before calculating minAway in \_tickForMultiple(). This prevents order creation from reverting when the current pool tick is not aligned to the pool's tick spacing.

- d2703bab: Fix stack too deep compilation error with internal refactoring of limit order creation.
- 851ca567: Fix router to fill pre-existing limit orders even when no new orders are created in the current swap

  Previously, the router would skip filling crossed limit orders if `orders.length == 0` (no new orders created in current transaction). This prevented legitimate fills of pre-existing orders that were crossed by the swap. The fix removes this incorrect condition, allowing the router to properly fill any orders crossed during the swap, regardless of whether new orders were also created.

- 4ce5e4b6: Fix maxFillCount bounds checking to always cap it at the default max fill count, event if a higher value is passed.
- 9486742f: Rename liqDelta to callerDelta for clearer naming fixes #19
- 2cb9cb30: Remove fixed MIN_LIMIT_ORDER_SIZE threshold that made many tokens unusable. Limit orders now accept any positive amount instead of requiring at least 1e18 tokens, fixing compatibility issues with tokens using different decimal configurations.
- eec53af3: Remove unnecessary Permit2Payments inheritance and use direct PERMIT2 immutable reference instead. This simplifies the contract structure by eliminating unused inherited functions while maintaining identical functionality.
- 83726a0e: Remove unused settle negative deltas logic

  - Remove redundant `_settleNegativeDeltas` function that was never executed
  - Simplify limit order closure logic by removing unnecessary delta settlement

- 0a104aa2: Fix potential hash collision in order ID generation

  Changed order ID derivation from `abi.encodePacked` to `abi.encode` to prevent potential hash collisions and ensure consistent hashing behavior. This security fix addresses audit finding MKT-47.

- b718117b: Fix limit order fulfillment to use correct currency when resolving payout paths

  Limit order fulfillment now correctly consults the output currency's payout path configuration instead of the input currency's configuration. This ensures orders receive payouts based on the token being purchased rather than the token being sold, preventing potential currency mismatches when both tokens in a pair have different custom payout paths configured.

- d6323749: Simplify limit order filling logic by deriving fill direction from tick movement. The system now automatically determines the correct currency direction based on tick changes (increasing tick = currency0, decreasing tick = currency1) instead of using complex tick sorting logic. This fix resolves issues where limit orders would revert when ticks were in unexpected order.
- 2b054307: Fix limit order payout handling for dual positive deltas. Previously, when limit order positions accumulated fees in both tokens (dual positive deltas), the payout would revert with a `CurrencyNotSettled` error because only one currency was withdrawn from the pool manager. The fix swaps the non-payout currency to the payout currency and pays out the combined amount, properly settling both deltas.
- 05579fbc: Refetch pool tick before filling each order to ensure accurate tick validation

  Improved the limit order filling logic to prevent orders from being filled with stale tick data. The fix adds a current tick refresh before checking if an order has crossed the current tick price during the execution loop. This ensures that orders are only filled when they have actually crossed the current tick price, preventing incorrect fills due to price movements during the fill operation.

- 5303b406: Fix native ETH settlement to prevent potential DoS by synchronizing pool manager state before settlement. This ensures accurate ETH balance tracking and prevents transaction failures when processing limit orders with native ETH.
- 16b3146c: Add WETH support for native ETH payouts in limit orders. When limit orders are filled or withdrawn with native ETH as the payout currency, the system now automatically wraps ETH into WETH before sending to recipients. This ensures compatibility with wallets and smart contracts that cannot receive native ETH directly, preventing transaction failures.

  **Breaking Change**: The `ZoraLimitOrderBook` constructor now requires an additional `weth` parameter. This affects deployment scripts and deterministic address computation.

## 0.2.0

### Minor Changes

- c59a6fac: Initial release of limit orders protocol

  Introduces a limit order system built on top of Uniswap V4 concentrated liquidity positions:

  - **Orders as V4 Positions**: Each limit order is a single-tick-wide Uniswap V4 liquidity position, enabling makers to place orders at specific price points
  - **FIFO Queue System**: Orders are organized in queues by `(poolKeyHash, coin, tick)` with bitmap-based tick tracking for efficient iteration
  - **Epoch-Based Fill Protection**: Orders cannot be filled in the same epoch they were created, preventing same-transaction manipulation

  **Fill Integration Modes:**

  - **Auto-fill via Hook**: The Zora hook now calls `fill()` on the limit order book during `afterSwap`, automatically filling orders as swaps cross through their tick ranges
  - **Router Fallback**: For legacy hooks, the router can call `fill()` post-swap
  - **Third-party Fill**: Anyone can call `fill()` when the PoolManager is locked, incentivized by LP fee collection

  **Fee Model:**

  - Fill referrals receive accrued LP fees from filled positions
  - Makers receive full proceeds on withdrawal
  - Makers can cancel their limit orders to withdraw the backing currency
