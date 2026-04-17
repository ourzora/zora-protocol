---
"@zoralabs/cli": minor
---

Add `zora get trades <coin>` subcommand showing recent buy/sell activity on a coin

- New `get trades` subcommand with `--live`, `--static`, and `--json` output modes, cursor-based pagination (`--limit`, `--after`), and auto-refresh support
- Add Trades tab to the main `zora get` live view alongside Price History, switchable with arrow keys or number keys
- JSON output of `zora get` now includes a `trades` array with recent swap activity
