---
"@zoralabs/incentive-contracts": patch
---

Remove indexed label from AllocationsSet event to prevent indexer parsing error

- Remove `indexed` keyword from `label` parameter in `AllocationsSet` event
- This prevents potential issues with event indexing and parsing
