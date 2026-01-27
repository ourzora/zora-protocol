# Zora Limit Orders — Audit Notes

This document highlights areas of concern for security reviewers.

Related docs:

- [`README.md`](./README.md) — architecture & diagrams
- [`SPEC.md`](./SPEC.md) — normative behavior + invariants

---

## Code Hotspots

Highest-risk logic:

- `src/ZoraLimitOrderBook.sol` — entrypoints + unlock routing
- `src/libs/LimitOrderFill.sol` — epoch + bitmap + queue traversal
- `src/libs/LimitOrderQueues.sol` — linked list operations
- `src/libs/LimitOrderBitmap.sol` — tick discovery
- `src/libs/LimitOrderLiquidity.sol` — settlement + payouts

---

## Areas of Concern

1. **Linked list integrity** — queue corruption could strand funds
2. **Bitmap correctness** — tick iteration edge cases and word boundaries
3. **Epoch isolation** — same-transaction fill prevention, especially with nested creates
4. **Settlement correctness** — currency deltas must settle in all paths (ERC20/native)
5. **Access control** — admin must not be able to access user funds or block withdrawals
6. **Reentrancy surface** — unlock callbacks, token transfers, hook interactions
7. **Gas/DoS** — pathological queues, maxFillCount edge cases
