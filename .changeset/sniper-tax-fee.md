---
"@zoralabs/coins": minor
---

Add launch fee: time-based dynamic fee that decays from 99% to 1% over 10 seconds after coin creation

- New coins record creation timestamp and expose it via `IHasCreationInfo` interface
- Hook calculates dynamic fee based on elapsed time since creation
- Initial supply purchase bypasses the fee via transient storage flag
- Legacy coins without the interface receive normal 1% LP fee
