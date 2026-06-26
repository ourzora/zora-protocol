---
"@zoralabs/cli": patch
---

Fix the `agent coin` help text to reference the correct flag. It previously pointed users to a non-existent `--with-coin` flag on `agent create`; creator coins are minted by default, so the guidance now correctly points to `--skip-coin`.
