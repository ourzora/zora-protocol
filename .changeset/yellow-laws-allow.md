---
"@zoralabs/limit-orders": patch
---

Replace AccessManager with PermittedCallers + Ownable2Step for access control in ZoraLimitOrderBook and SwapWithLimitOrders contracts.

- Remove AccessManager and SimpleAccessManaged pattern
- Use OpenZeppelin Ownable2Step for two-step ownership transfer
- Add `permittedCallers` mapping to gate `create()` access (public by default, owner can restrict)
- Add `isPermittedCaller()` getter and `setPermittedCallers()` batch setter functions
- Owner (multisig) retains access to `setMaxFillCount()` and `setLimitOrderConfig()` functions
