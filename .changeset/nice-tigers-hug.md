---
"@zoralabs/cli": minor
---

Add paginated `profile posts` and `profile holdings` subcommands

- `zora profile posts [identifier]` — browse a profile's created coins with cursor-based pagination
- `zora profile holdings [identifier]` — browse a profile's coin holdings with pagination and sorting (`--sort usd-value|balance|market-cap|price-change`)
- Both subcommands support `--limit`, `--after`, `--live`, `--static`, `--refresh`, and `--json` flags
