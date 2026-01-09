# Zora Limit Orders — Protocol Spec (Auditor & Integrator Facing)

This document is the **behavioral specification** for the Limit Orders system in `packages/limit-orders/`.

Related docs:

- [`README.md`](./README.md) — architecture & diagrams (canonical “where to start”)
- [`AUDIT_NOTES.md`](./AUDIT_NOTES.md) — threat model & audit checklist
- [`AUDIT_RFP.md`](./AUDIT_RFP.md) — audit scope & deliverables

---

## 1. Glossary

- **PoolKey / poolKeyHash**: Uniswap V4 pool identity / hash.
- **tick**: Discrete price index for concentrated liquidity.
- **tickSpacing**: The pool’s tick granularity; all order ticks are aligned to it.
- **order**: A single-sided liquidity position representing a limit order.
- **queue**: FIFO linked-list of orders at a given `(poolKeyHash, coin, tick)`.
- **bitmap**: Tracks which ticks have active queues for a given `(poolKeyHash, coin)`.
- **epoch**: Monotonic counter per pool used to prevent same-transaction fill of newly-created orders.
- **maker**: Address that creates an order and receives proceeds/refunds.
- **filler**: Address/contract that triggers filling (hook, router, or third party).

---

## 2. System Overview (Normative)

### 2.1 Orders as Uniswap V4 positions

Each order corresponds to a Uniswap V4 position:

- **Range**: one tickSpacing-wide range: \([tickLower, tickUpper]\) with `tickUpper = tickLower + tickSpacing` (direction-dependent).
- **Salt**: derived from `orderId` (orderId is deterministic).
- **Funds**: deposited as one side of the range; the other side is received when filled via swaps/burn.

### 2.2 Order status model

Orders have statuses:

- `OPEN`: active in queue + has liquidity position.
- `FILLED`: liquidity removed/settled; proceeds attributed/paid out.
- `INACTIVE`: cancelled/withdrawn (not fillable).

Allowed transitions (conceptual):

- `OPEN -> FILLED`
- `OPEN -> INACTIVE`

No other transitions should be possible.

---

## 3. External API Spec (Normative)

This section defines **intended behavior** for the public entrypoints. For exact types/events/errors, reference `src/IZoraLimitOrderBook.sol`.

### 3.1 `create(...)`

[`ZoraLimitOrderBook.sol:69`](./src/ZoraLimitOrderBook.sol#L69) → [`LimitOrderCreate.sol:44`](./src/libs/LimitOrderCreate.sol#L44)

**Purpose**

- Adds single-sided V4 liquidity positions for each requested order, and records them into the onchain order book.

**Authorization**

- `create()` is access-controlled via `SimpleAccessManaged` authority checks.

**Effects**

- For each order:
  - Transfers funds from maker to the system (direct transfer or Permit2 path depending on router/integration).
  - Mints V4 liquidity for the order range, using `orderId` as salt.
  - Records a `LimitOrder` struct, inserts it into its `(poolKeyHash, coin, tick)` queue, and sets bitmap bit if first at tick.
  - Updates maker balance accounting for `balanceOf()` style queries.
  - Refunds any rounding dust per implementation rules.

**Failure modes (examples; non-exhaustive)**

- Unauthorized caller.
- Invalid tick alignment / range.
- Invalid pool key / unsupported currencies.
- Insufficient funds / transfer failures.
- Invalid order configuration.

### 3.2 `fill(...)` (range-based)

[`ZoraLimitOrderBook.sol:81`](./src/ZoraLimitOrderBook.sol#L81) → [`LimitOrderFill.sol:60`](./src/libs/LimitOrderFill.sol#L60)

**Purpose**

- Fills as many orders as possible within a tick range (bounded by `maxFillCount`), removing their liquidity and paying proceeds.

**Authorization**

- When PoolManager is **unlocked**: restricted (only registered hooks, per implementation).
- When PoolManager is **locked**: callable by anyone.

**Epoch isolation**

- At the start of a fill execution for a pool, epoch increments.
- Any order created in the **current** epoch must not be fillable until a later epoch.

**Effects**

- Iterates ticks with active queues via bitmap, traverses queues FIFO, and processes up to `maxFillCount` fills.
- For each filled order:
  - Removes order from queue and clears bitmap bit if tick becomes empty.
  - Burns liquidity, performs required swap path (if configured), and pays out maker and referral amounts per configured rules.
  - Marks order status as `FILLED`.

### 3.3 `fill(...)` (orderId-based)

[`ZoraLimitOrderBook.sol:125`](./src/ZoraLimitOrderBook.sol#L125) → [`LimitOrderFill.sol:60`](./src/libs/LimitOrderFill.sol#L60)

**Purpose**

- Fills specific order IDs (bounded by `maxFillCount` or batch size per implementation).

**Authorization**

- Same unlocked/locked restrictions as range-based fill.

**Effects**

- For each order ID:
  - Validates order status and pool binding.
  - Applies epoch rule (order cannot be filled in its creation epoch).
  - Burns liquidity + pays out, and updates queue/bitmap/bookkeeping.

### 3.4 `withdraw(orderIds, coin, minAmountOut, recipient)`

[`ZoraLimitOrderBook.sol:141`](./src/ZoraLimitOrderBook.sol#L141) → [`LimitOrderWithdraw.sol:26`](./src/libs/LimitOrderWithdraw.sol#L26)

**Purpose**

- Cancels specific maker orders by ID and withdraws resulting funds to `recipient` (optionally meeting `minAmountOut`).

**Authorization**

- Maker-only (must own each order being withdrawn).

**Effects**

- Processes `orderIds` sequentially until either:
  - `minAmountOut` is reached, or
  - all provided orders are processed.
- For each cancelled order:
  - Removes order from queue and clears bitmap bit if tick becomes empty.
  - Burns liquidity and refunds (or swaps to payout currency, depending on configuration).
  - Marks order as `INACTIVE`.

**Important behavioral clarifications (should remain true)**

- Withdrawal is **whole-order only** (no partial cancellation).
- User funds are always withdrawable regardless of create/fill admin settings (assuming underlying Uniswap V4 invariants hold).

### 3.5 Admin functions

**`setMaxFillCount(uint256 newMaxFillCount)`**

- Updates the stored default max fills per call.
- Must not allow admin to withdraw user funds or block withdrawals.

**Authority management**

- Authority contract can be updated as per `SimpleAccessManaged` design.

---

## 4. Storage & Indexing (Normative)

### 4.1 Primary indices

- **Orders**: `orderId -> LimitOrder`
- **Queues**: `(poolKeyHash, coin, tick) -> Queue(head, tail, length, balance)`
- **Bitmap**: `(poolKeyHash, coin) -> tick bitmap words`
- **Epoch**: `poolKeyHash -> epoch`
- **Maker balances**: `(maker, coin) -> makerBalance`
- **Nonces**: `maker -> nonce` (for deterministic order IDs)

### 4.2 Deterministic order ID

Order IDs are deterministic hashes of the identifying tuple (see implementation in `LimitOrderCreate.sol`).

---

## 5. Protocol Invariants (Auditor Checklist)

This is the “must always hold” list auditors should continuously verify.

### 5.1 Queue invariants

- **Head/tail consistency**:
  - If `length == 0`: `head == 0` and `tail == 0`.
  - If `length > 0`: `head != 0` and `tail != 0`.
- **Link integrity**:
  - No cycles in `nextId`/`prevId`.
  - `head.prevId == 0` and `tail.nextId == 0`.
  - For each node: `orders[next].prevId == current` and `orders[prev].nextId == current` (when those neighbors exist).
- **FIFO**:
  - Enqueue appends at `tail`.
  - Fills traverse from `head` forward.
- **Balance accounting**:
  - `Queue.balance` equals sum of `orderSize` (or intended accounting field) across `OPEN` orders in that queue.

### 5.2 Bitmap invariants

- A bitmap bit for a tick is **set iff** the queue at that tick has `length > 0`.
- Removing the last order at a tick clears the bit.
- Word-boundary transitions in tick iteration must not skip active ticks or loop infinitely.

### 5.3 Epoch invariants

- Epoch is per-pool and monotonically increases only at the start of fill executions.
- An order created in epoch `e` cannot be filled during epoch `e`.
- Nested create-during-fill must not allow immediate same-epoch fill (intent: deferred to next fill).

### 5.4 Order status invariants

- `OPEN` orders must be present in exactly one queue, and that queue key must match the order’s `(poolKeyHash, coin, tickLower/tick)` binding.
- `FILLED` / `INACTIVE` orders must not remain linked in a queue.

### 5.5 Maker balance invariants

- For a given `(maker, coin)`, `makerBalance` must equal the sum of `orderSize` (or intended accounting field) over all `OPEN` orders owned by maker for that coin.
- Any decrement must happen exactly once on fill or withdraw/cancel.

### 5.6 Uniswap V4 settlement invariants (integration)

- All currency deltas created by `modifyLiquidity`, `swap`, `take`, `settle`, and `sync` within an unlock must be settled before completion.
- The contract must not rely on external token balances changing mid-unlock in unexpected ways.

---

## 6. Observability (Events & Indexing)

Auditors/integrators should validate that emitted events are sufficient to:

- Track created orders (orderId, maker, pool key binding, tick, size, direction).
- Track fills (orderId, amounts out, fees, referral).
- Track withdrawals/cancellations.

If events are insufficient for an indexer to reconstruct state, document the intended “indexer model” explicitly (event-sourced vs state-queried).

---

## 7. Fee & Incentive Model (Normative)

### 7.1 How fees accrue

Each limit order is a Uniswap V4 liquidity position. While the order is open and swaps occur through the pool, the position accrues LP fees from trades that cross through its tick range.

### 7.2 Fee distribution on fill

When an order is filled, the `fill()` function accepts a `fillReferral` parameter:

- **If `fillReferral == address(0)`**: All proceeds (liquidity + accrued fees) go to the maker.
- **If `fillReferral != address(0)`**: The maker receives the liquidity proceeds, and the fill referral receives the accrued LP fees.

This creates an incentive for third parties to fill orders — they can claim the LP fees that have accumulated on the position.

### 7.3 Fee distribution on withdrawal

When a maker withdraws (cancels) their order via `withdraw()`:

- The maker receives all proceeds (liquidity + any accrued fees).
- No fill referral is involved since the maker is cancelling their own order.

### 7.4 Incentive structure

| Actor              | Incentive                                                         |
| ------------------ | ----------------------------------------------------------------- |
| Maker              | Receives swap proceeds when order fills; can withdraw at any time |
| Fill Referral      | Receives accrued LP fees from filled positions                    |
| Third-party Filler | Can pass their own address as `fillReferral` to collect fees      |

This design ensures orders will eventually be filled even without hook or router integration — third parties are economically incentivized to monitor and fill orders to capture the accrued fees.

---

## 8. Integration Modes

Three fill paths exist (detailed in README):

- **Auto-fill via hook** (new hook versions calling `fill` during `afterSwap`).
- **Router fill fallback** for legacy hooks (router calls `fill` post-swap).
- **Third-party fill** for pools without hook integration or swaps bypassing the router.

Integrators should confirm which path applies for their pool/hook versioning and whether the hook registry restriction applies during unlock.
