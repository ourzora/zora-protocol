---
"@zoralabs/cli": minor
---

Add `get holders` subcommand to show top holders of a coin with balance and % of total supply

- Supports `--json`, `--live` (interactive with pagination), and `--static` output modes
- Adds a Holders tab to the `zora get` live view alongside Price History
- Supports `--limit` (1-20, default 10), `--after` cursor pagination, and type prefix arguments
