---
"@zoralabs/limit-orders": minor
---

Initial release of limit orders protocol

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
