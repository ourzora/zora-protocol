---
"@zoralabs/coins": patch
---

Fix liquidity migration bug: when migrating liquidity to a hook with a different fee, the old fee was kept. This will now make sure that the new fee is used after migration.  Also make sure to use the new tick spacing after migration.
