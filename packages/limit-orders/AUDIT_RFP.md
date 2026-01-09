# Zora Protocol Limit Orders (aka "Autosell") - Audit Scope Document

**Version**: 1.2
**Date**: 2025-12-12
**Branch**: `autosell`
**Purpose**: Audit scope and technical reference for engaged auditors

---

## Executive Summary

Zora has implemented a limit orders system that enables users to create onchain
orders that automatically execute when Uniswap V4 pool prices reach
predetermined ticks. This document provides complete scope, technical analysis,
and security considerations for the audit engagement.

**Scope**: ~2,758 lines of Solidity across 16 new files
**Focus Areas**: Linked list integrity, epoch-based execution isolation, bitmap optimization, access control
**Ideal Auditor Profile**: Strong familiarity with DeFi protocols and Uniswap V4 architecture (liquidity positions, hook patterns, unlock callbacks, transient storage)

---

## Technical Architecture Reference

**Supporting docs**

- [`README.md`](./README.md) — architecture, diagrams, execution paths
- [`SPEC.md`](./SPEC.md) — normative behavior and invariants (“what must be true”)
- [`AUDIT_NOTES.md`](./AUDIT_NOTES.md) — threat model + audit checklist

This RFP focuses on audit scope, security considerations, and deliverables.

---

## Quick Navigation

### Part 1: Audit Scope & Process

- [Audit Scope](#part-1-audit-scope) - What's in/out of scope
- [Areas of Technical Complexity](#areas-of-technical-complexity) - Implementation details
- [Audit Deliverables](#audit-deliverables)
- [Timeline & Process](#timeline-and-process)
- [Clarifications Needed](#clarifications-needed)

### Part 2: Technical Implementation

- [File Structure](#file-structure) - All 15 files documented
- [Data Structures](#data-structures) - LimitOrder, Queue, Order IDs
- [Storage Organization](#storage-organization) - Storage layout
- [External Functions](#external-functions) - create, fill, withdraw

### Part 3: Additional Information

- [Known Limitations](#known-limitations)

---

# PART 1: AUDIT SCOPE

## Overview

_For detailed architecture, see [README: Overview](./README.md#1-overview) and [Limit Orders Architecture](./README.md#3-limit-orders-architecture-overview)_

The limit orders system allows users to:

1. **Create orders** by adding Uniswap V4 liquidity positions across a one-tick-spacing range
2. **Fill orders** automatically when pool price crosses into the order's range
3. **Withdraw orders** by cancelling specific orders by ID and withdrawing the resulting funds to a recipient.
   - The call cancels orders in the order provided until `minAmountOut` is reached (or cancels all provided orders if `minAmountOut == 0`).
   - Cancellation is whole-order only (no proportional/partial cancellation).

**Key Innovation**: Implements limit orders as single-sided Uniswap V4 liquidity positions, providing a completely native onchain approach that keeps liquidity in the pools for improved trading. Uses linked list queues, bitmap optimization, and epoch-based execution isolation for efficient order matching.

## In-Scope Contracts

### Primary Package: `packages/limit-orders/src/`

#### Core Contracts (2 files, ~418 LOC)

**ZoraLimitOrderBook.sol** (229 lines)

- Main contract implementing the order book
- Manages pool manager unlock/callback patterns
- Delegates to library contracts for execution
- Access control via SimpleAccessManaged

**IZoraLimitOrderBook.sol** (189 lines)

- Public API interface and event definitions
- 3 callback types: CREATE, FILL, WITHDRAW_ORDERS
- 21 error types for validation
- Data structure definitions for callbacks

#### Access Control (2 files, ~345 LOC)

**access/SimpleAccessManaged.sol** (76 lines)

- Lightweight fork of OpenZeppelin's [AccessManaged](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessManaged) contract, reduced in complexity to minimize code size
- Uses the same security architecture (authority-based permissions via `IAuthority.canCall()`)
- Removes time-based permissions methodology (no delays, no scheduled operations)
- Controls `create()` and `setMaxFillCount()` functions

**access/SimpleAccessManager.sol** (268 lines)

- Full role-based access manager implementation
- Provides complete `IAuthority` interface implementation
- Supports role-based permissions with admin delegation
- `PUBLIC_ROLE` support for unrestricted functions
- Function selector mapping to specific roles

#### Type Definitions & Storage (2 files, ~79 LOC)

**LimitOrderTypes.sol** (44 lines)

- OrderStatus enum: INACTIVE, OPEN, FILLED
- LimitOrder struct (224 bytes / 7 storage slots with linked list pointers)
- Queue struct (96 bytes / 3 storage slots with head/tail/length/balance)

**LimitOrderStorage.sol** (35 lines)

- Storage slot derived from `keccak256("zora.limit.order.book.storage")`
- Storage slot: `0x98b43bb10ca7bc310641b07883d9e14c04b3983640df6b07dd1c99d10a3c6cec`
- Layout with 6 mappings for orders, queues, epochs, bitmaps, nonces, and maker balances

#### Order Lifecycle Libraries (3 files, ~722 LOC)

**LimitOrderCreate.sol** (277 lines)

- Order creation with validation
- Calls `poolManager.modifyLiquidity()` with positive `liquidityDelta` to add liquidity
- Manages callback data and execution
- Handles residual amount refunds
- Implementation details: Input validation, liquidity calculations, nonce management

**LimitOrderFill.sol** (345 lines)

- Core fill execution logic
- Epoch-based execution isolation mechanism
- Two fill modes: tick range-based and order ID-based
- Bitmap-based tick iteration optimization
- Assembly optimizations in tight loops
- Implementation details: Epoch checks, bitmap manipulation, linked list traversal

**LimitOrderWithdraw.sol** (100 lines)

- Cancellation and withdrawal logic
- Order-specific withdrawal (cancels provided order ids sequentially until `minAmountOut` is reached)
- Burns liquidity and issues refunds
- Implementation details: Owner validation, balance accounting, liquidity burning

#### Support Libraries (6 files, ~648 LOC)

**LimitOrderCommon.sol** (91 lines)

- Order metadata extraction helpers
- Records orders in queues and bitmaps
- Removes orders from queues and bitmaps
- Tick determination logic

**LimitOrderQueues.sol** (101 lines)

- Linked list implementation
- Single tick queue system
- Operations: enqueue, unlink, clearLinks
- Direct storage slot manipulation for gas optimization
- Implementation details: Linked list integrity, concurrent modifications

**LimitOrderBitmap.sol** (84 lines)

- Bitmap management for tick activation tracking
- Sets/clears bits when ticks become active/inactive
- `getExecutableTicks()` for efficient range queries
- Implementation details: Bit manipulation correctness, boundary conditions

**LimitOrderLiquidity.sol** (222 lines)

- Uniswap V4 liquidity management
- Helper functions for adding liquidity during order creation (`_mintLiquidity()`)
- Removes liquidity during fills/cancels (`burnAndPayout()`, `burnAndRefund()`)
- Handles fee distribution and swap paths
- Supports alternative payout currencies
- Implementation details: Liquidity calculations, fee distribution, swap execution

**SwapLimitOrders.sol** (209 lines)

- Configuration for automatic order creation post-swap
- Validates multiples and percentages
- Computes order ladders from price multiples
- Square root math for price alignment

**Permit2Payments.sol** (41 lines)

- Abstract contract for Permit2 token transfers
- Based on Uniswap's universal-router module
- Enables gasless token approvals

#### Router Contract (1 file, ~454 LOC)

_See [README: SwapWithLimitOrders Router](./README.md#2-swapwithlimitorders-router) for detailed architecture_

**router/SwapWithLimitOrders.sol** (454 lines)

- Standalone router for combined operations
- Executes V3→V4 swaps + order creation + fills
- Implements pool manager callback pattern
- Attempts to fill orders if price crosses

### Integration Points: `packages/coins/src/`

_For Zora Coins platform architecture, see [README: Coins Platform Architecture](./README.md#2-coins-platform-architecture)_

#### Modified Hook Contract

**hooks/ZoraV4CoinHook.sol** (modifications only)

- Integration point for automatic limit order fills during swaps
- Calls `limitOrderBook.fill()` in `afterSwap` hook
- Passes fill referral information

**Related Support Libraries**:

- `libs/V3ToV4SwapLib.sol` - V3 migration support
- `libs/CoinRewardsV4.sol` - Reward distribution

## Out-of-Scope

### Explicitly Excluded

**Deployment Scripts**:

- `packages/coins/src/deployment/CoinsDeployerBase.sol`
- All files in `script/` directories across all packages
- All deployment infrastructure and tooling

**Test Files**:

- All files in `test/` directories (except as behavioral reference)
- Test utilities and mocks

**Legacy Code**:

- `legacy/` directory contents
- Deprecated contracts from previous versions

**Documentation & Tooling**:

- `docs/` and `nft-docs/` directories
- Build scripts and configuration files
- SDK packages (`coins-sdk`, `protocol-deployments`)

**External Dependencies** (auditing the dependencies themselves is out of scope, but integration risks are a key focus):

- Uniswap V4 core contracts (`@uniswap/v4-core`) - **Integration analysis is critical**: how we interact with pool manager, liquidity operations, unlock callbacks, and balance settlements
- OpenZeppelin contracts (`@openzeppelin/contracts`) - Used for IAuthority, IERC20, SafeERC20, TransientSlot

**Critical Integration Patterns to Audit**:

We are particularly interested in identifying risks in how our code interacts with Uniswap V4:

- **Unlock callback patterns**: nested unlock handling when orders are created during fills (see `LimitOrderCreate.sol:44`), potential reentrancy through callbacks, unlock state verification
- **Liquidity position management**: salt-based position isolation using orderIds as salts (see `LimitOrderCreate.sol:200`, `LimitOrderLiquidity.sol:64`), tick range calculations, liquidity delta correctness
- **Balance accounting**: settle/take/sync patterns (see `LimitOrderLiquidity.sol`), currency delta tracking via `TransientStateLibrary.currencyDelta`, ETH vs ERC20 handling
- **Transient storage usage**: `isUnlocked` checks for access control (see `ZoraLimitOrderBook.sol:90`), currency delta reading for settlement verification
- **Position lifecycle**: `modifyLiquidity` calls with positive delta (mint) and negative delta (burn), fee accumulation via `feesDelta` and distribution to makers/referrals

## Areas of Technical Complexity

**Linked List Implementation** ([`LimitOrderQueues.sol`](src/libs/LimitOrderQueues.sol), [`LimitOrderCommon.sol`](src/libs/LimitOrderCommon.sol)) - See [README: Tick Queue System](./README.md#tick-queue-system): Tick-based linked lists enable O(1) insertion/removal when order ID is known. Orders are indexed by `(poolKeyHash, coin, tick)` for efficient fill operations.

**Epoch-Based Execution Isolation** ([`LimitOrderFill.sol`](src/libs/LimitOrderFill.sol), [`LimitOrderStorage.sol`](src/libs/LimitOrderStorage.sol)) - See [README: Epoch-Based Protection](./README.md#epoch-based-protection): Orders cannot be filled in the same epoch they were created. Each pool maintains an independent epoch counter (uint256) that increments at the start of each fill. Orders store uint32 createdEpoch and are skipped if `createdEpoch >= currentEpoch`. This ensures orders created during fill execution wait for the next fill operation.

**Bitmap Optimization** ([`LimitOrderBitmap.sol`](src/libs/LimitOrderBitmap.sol), [`LimitOrderCommon.sol`](src/libs/LimitOrderCommon.sol)) - See [README: Tick Discovery](./README.md#tick-discovery-bitmap-implementation): Active ticks tracked via bitmap structure for gas-efficient iteration. One bitmap per (poolKeyHash, coin) combination with word-based storage (256 ticks per uint256). Uses Uniswap's TickBitmap library for word-boundary traversal.

**Access Control** ([`SimpleAccessManaged.sol`](src/access/SimpleAccessManaged.sol)) - See [README: Access Control](./README.md#access-control-via-simpleaccessmanaged): Lightweight fork of OpenZeppelin's [AccessManaged](https://docs.openzeppelin.com/contracts/5.x/api/access#AccessManaged) that removes time-based permissions. Protects `create()` and `setMaxFillCount()` via authority contract's `canCall()` interface. Fill operations have additional restrictions during pool unlock (only registered hooks).

**Liquidity Management** ([`LimitOrderLiquidity.sol`](src/libs/LimitOrderLiquidity.sol), [`LimitOrderCreate.sol`](src/libs/LimitOrderCreate.sol), [`LimitOrderWithdraw.sol`](src/libs/LimitOrderWithdraw.sol)) - See [README: Single-Sided Liquidity](./README.md#single-sided-liquidity): Orders implemented as Uniswap V4 liquidity positions across one-tick-spacing ranges using orderID as salt. Supports ERC20 and ETH, alternative payout currencies via swap paths, residual refunds, and fee distribution to makers/referrals.

**Unlock Callback Pattern** ([`ZoraLimitOrderBook.sol`](src/ZoraLimitOrderBook.sol)) - See [README: Component Interaction Flows](./README.md#component-interaction-flows): All state-changing operations occur within Uniswap V4's unlock callback mechanism. Three callback types: CREATE, FILL, WITHDRAW_ORDERS. All balance changes must be settled atomically before unlock completes.

**Token Accounting** ([`LimitOrderLiquidity.sol`](src/libs/LimitOrderLiquidity.sol)) - See [README: Component Interaction Flows](./README.md#component-interaction-flows): Handles ERC20 and native ETH transfers through pool manager's sync/settle/take pattern with balance verification before and after transfers.

**Gas Optimization** ([`LimitOrderFill.sol`](src/libs/LimitOrderFill.sol)): `maxFillCount` parameter limits orders processed per call. Bitmap optimization skips empty ticks. Assembly optimizations in hot loops. Multiple fill calls may be needed for large queues (100+ orders).

**Security Model** - See [README: Security Model & Guarantees](./README.md#5-security-model--guarantees): Documents protocol security guarantees, actor analysis, admin capabilities/limitations, and why `create()` is access controlled.

**DOS Prevention** - See [README: Gas Limits & DOS Prevention](./README.md#6-gas-limits--dos-prevention): Details on `maxFillCount` parameter, gas analysis from testing, and Fusaka/future hard fork considerations.

**Fill Execution Paths** - See [README: Fill Execution Paths](./README.md#4-fill-execution-paths): Documents the three distinct fill paths (auto-fill from hook, router fill, third-party fill), hook migration requirements, and universal Uniswap V4 compatibility.

## Code Statistics

**Solidity Code**:

- Core implementation: ~2,758 lines
- Primary contract: 220 lines
- Libraries: ~1,689 lines
- Interface: 195 lines
- Access control: 344 lines (SimpleAccessManaged + SimpleAccessManager)
- Router: 454 lines

**Test Files**: 6 test contracts in `packages/limit-orders/test/`

**Modified Existing Code**:

- ZoraV4CoinHook.sol: ~50-100 lines modified for integration
- Supporting libraries: TBD based on actual changes

**Note for Auditors**: Understanding the integration points will require familiarity with the existing Zora Coins protocol architecture (hooks, reward distribution, coin versioning). Auditors should account for time to review relevant portions of `packages/coins/` in their proposals.

## Audit Deliverables

We are looking for a comprehensive security assessment that includes:

- **Security findings** with severity classifications, impact analysis, and remediation recommendations
- **Integration risk assessment** focusing on Uniswap V4 interactions and Zora Coins protocol integration
- **Code quality analysis** including gas optimization opportunities and best practices
- **Testing artifacts** such as custom test cases, fuzzing results, or static analysis outputs developed during the audit

---

# PART 2: TECHNICAL IMPLEMENTATION

## File Structure

### Complete Package Organization

```
packages/limit-orders/src/
├── ZoraLimitOrderBook.sol          (220 lines) - Main contract
├── IZoraLimitOrderBook.sol         (195 lines) - Interface
├── access/
│   ├── SimpleAccessManaged.sol     (76 lines)  - Access control base
│   └── SimpleAccessManager.sol     (268 lines) - Role-based access manager
├── libs/
│   ├── LimitOrderCreate.sol        (277 lines) - Creation logic
│   ├── LimitOrderFill.sol          (345 lines) - Fill logic (MOST COMPLEX)
│   ├── LimitOrderWithdraw.sol      (100 lines) - Withdrawal logic
│   ├── LimitOrderStorage.sol       (34 lines)  - Storage layout
│   ├── LimitOrderTypes.sol         (41 lines)  - Type definitions
│   ├── LimitOrderCommon.sol        (91 lines)  - Common utilities
│   ├── LimitOrderQueues.sol        (101 lines) - Linked list ops
│   ├── LimitOrderBitmap.sol        (84 lines)  - Bitmap tracking
│   ├── LimitOrderLiquidity.sol     (222 lines) - Liquidity management
│   ├── SwapLimitOrders.sol         (209 lines) - Config helper
│   └── Permit2Payments.sol         (41 lines)  - Permit2 support
└── router/
    └── SwapWithLimitOrders.sol     (454 lines) - Router contract
```

## Data Structures

For detailed documentation of data structures (LimitOrder struct, Queue struct, OrderStatus enum) and the tick queue system, see the [README.md](./README.md#tick-queue-system).

**Order ID Generation**: Deterministic hash of `keccak256(abi.encode(poolKeyHash, coin, tick, maker, nonce))` where nonce increments per maker.
(_Implementation detail_: `LimitOrderCreate.sol` hashes 5x 32-byte words, equivalent to `abi.encode(...)` rather than `abi.encodePacked(...)`.)

**Callback Data Structures** ([`IZoraLimitOrderBook.sol`](src/IZoraLimitOrderBook.sol)): OrderBatch, CreateCallbackData, FillCallbackData, WithdrawOrdersCallbackData

## Storage Organization

Uses diamond storage pattern at slot `0x98b43bb10ca7bc310641b07883d9e14c04b3983640df6b07dd1c99d10a3c6cec`. For details on storage layout and the diamond pattern implementation, see [`LimitOrderStorage.sol`](src/libs/LimitOrderStorage.sol) and [README.md](./README.md#diamond-storage-pattern).

## External Functions

_See [README: Order Creation Flow](./README.md#order-creation-flow) and [Withdrawal Flow](./README.md#withdrawal-flow) for detailed interaction diagrams_

See [`IZoraLimitOrderBook.sol`](src/IZoraLimitOrderBook.sol) for full signatures and documentation.

**`create()`** ([ZoraLimitOrderBook.sol:73-82](src/ZoraLimitOrderBook.sol#L73-L82)): Creates new limit order(s) by adding liquidity via `poolManager.modifyLiquidity()`. Requires authorization via SimpleAccessManaged. Generates order IDs, records in queues, sets bitmap bits, handles residual refunds.

**`fill()` - Range-based** ([ZoraLimitOrderBook.sol:85-127](src/ZoraLimitOrderBook.sol#L85-L127)): Fills orders within a tick range. Anyone can call; restricted to registered hooks during pool unlock. Bumps epoch, traverses bitmap for active ticks, processes orders, burns liquidity, distributes payouts.

**`fill()` - Order-specific** ([ZoraLimitOrderBook.sol:129-142](src/ZoraLimitOrderBook.sol#L129-L142)): Fills specific orders by ID. Operates on explicit order ID batches.

**`withdraw()`** ([ZoraLimitOrderBook.sol:141-147](src/ZoraLimitOrderBook.sol#L141-L147)): Cancel specific orders by ID. Takes `orderIds`, `coin`, `minAmountOut`, and `recipient` parameters. Validates ownership and status, burns liquidity, issues refunds.

---

# PART 3: ADDITIONAL INFORMATION

## Known Limitations

1. **Multi-block scenarios**: Epochs only prevent same-transaction, not cross-block
2. **Gas Limits**: Large queues (100s/1000s of orders) may need multiple fills
3. **No Partial Fills**: Orders fill completely or not at all
4. **Tick Spacing**: Limited by pool's tick spacing

---

# CONCLUSION

The Zora Limit Orders implementation uses sophisticated data structures (linked lists, bitmaps) to provide an onchain order book integrated with Uniswap V4.

## Next Steps for Auditors

1. Review this document and supporting docs ([README.md](./README.md), [SPEC.md](./SPEC.md), [AUDIT_NOTES.md](./AUDIT_NOTES.md))
2. Familiarize yourself with Uniswap V4 architecture if needed
3. Begin review with code hotspots identified in [AUDIT_NOTES.md](./AUDIT_NOTES.md#1-code-hotspots-fast-path)
4. Submit questions or clarifications as needed

---

**Document Version**: 1.2
**Last Updated**: 2025-12-12
**Based On**: Actual implementation in `packages/limit-orders/`
**Branch**: `autosell`

For questions or clarifications, please contact [Will Binns](mailto:will.binns@ourzora.com).
