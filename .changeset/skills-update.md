---
"@zoralabs/cli": minor
---

Add ten new agent skills to `zora skills` and group every skill by category.

New skills (each installable with `zora skills add <name>`, or all at once with `--all`):

- **Discovery** — `trend-sniper` (snipe new trend coins off the global trending feed), `new-coin-screener` (auto-buy new launches that pass a market-cap/holder screen), `whale-watcher` (watch top holders and large trades, then alert or auto-trade)
- **Social** — `dm-responder` (triage and auto-reply to incoming DMs), `comment-engager` (read and reply to comments on coins you hold), `social-trader` (buy followed creators' new post coins or growing creator coins), `auto-poster` (publish posts on a schedule)
- **Risk** — `dca` (dollar-cost-average a fixed amount into chosen coins), `portfolio-rebalancer` (rebalance holdings back to target allocations)
- **Reporting** — `portfolio-digest` (read-only portfolio and PnL digest, optionally delivered to the operator by DM)

All skills (existing and new) now share the same format as the onboarding skill — a title, skill version, "What This Skill Does", and "Requirements" — and `zora skills list` orders them by category (Onboarding, Discovery, Social, Risk, Reporting) to match the docs.

The core CLI skill (`SKILL.md`) gains a `comment` section, the opt-in `agent coin` flow, the `balance` `walletAddress` field, and the `wallet info` smart-wallet field, and lists all skills grouped by category.
