---
"@zoralabs/cli": patch
---

- Add live data refresh with unified --output flag
- Add valueUsd, swapCoinType, transactionHash, logIndex to PostHog swap events
- Fix buy/sell commands to respect global --json flag
- Include USD value in PostHog swap events
- Use compact short notation for large balances
- Add price-history command
- Add responsive tables and interactive explore with live pagination
- Consolidate formatting utils and remove duplication
- Use spendableBalance for sub-100% --percent buy calculations
- Add beta warning banner to CLI output
