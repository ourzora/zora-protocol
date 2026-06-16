---
"@zoralabs/cli": minor
---

Add a global, wallet-level spending budget for agents that caps total spend across all trading skills, on top of each skill's own caps.

- New `zora agent budget` commands: `set <amount> [--period daily|weekly|lifetime]` (or `set --no-limit` to explicitly opt out), `info`, `check --usd|--eth`, `record`, and `reset`.
- The budget is stored in `~/.config/zora/budget.json` with an append-only spend ledger; spend is denominated in USD (ETH amounts are converted at the current price).
- The bundled trading skills (`dca`, `trend-sniper`, `copy-trader`, `early-buyer`, `social-trader`, `new-coin-screener`, `whale-watcher`) now check the global budget before each trade and record the spend after.
- Onboarding adds an explicit "Set Spend Budget" step so the spending cap is a conscious, up-front choice rather than a buried default.
