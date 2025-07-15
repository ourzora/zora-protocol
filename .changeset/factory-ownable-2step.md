---
"@zoralabs/coins": major
---

Move ZoraFactoryImpl to 2-step ownable with same storage slots

This change updates the factory contract to use Ownable2StepUpgradeable instead of OwnableUpgradeable. The change maintains storage slot compatibility while adding the two-step ownership transfer pattern for enhanced security.

Key changes:

- ZoraFactoryImpl now inherits from Ownable2StepUpgradeable
- Adds pendingOwner() function
- Requires acceptOwnership() call to complete ownership transfers
- Maintains storage slot compatibility for upgrades
