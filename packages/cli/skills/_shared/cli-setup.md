# Zora CLI Setup

Before running commands, detect how the Zora CLI is available:

1. Check if `zora` is on PATH: `which zora` or `command -v zora`
2. Check if installed via npm/pnpm: `npx @zoralabs/cli --version`
3. Fall back to `npx @zoralabs/cli` if nothing else works

Use whichever method succeeds. Throughout these skills, commands are written as `zora <command>` — substitute the actual invocation for your environment (e.g., `npx @zoralabs/cli`, `pnpm zora`, or just `zora`).

## Wallet Setup

Trade commands require a configured wallet. The CLI looks for a wallet in this order:

1. **Wallet file** (primary): Run `zora setup --create` or `zora wallet configure` to save a wallet to `~/.config/zora/wallet.json`
2. **Environment variable** (alternative): Set `ZORA_PRIVATE_KEY` (hex, with or without 0x prefix). Useful for CI or ephemeral environments.

Check wallet status with `zora wallet info --json`.

## Environment Variables

- `ZORA_PRIVATE_KEY` — Alternative to wallet file. Only needed if no wallet file is configured.
- `ZORA_API_KEY` — API key for higher rate limits (optional). Get one at zora.co/settings/developer.

## Common Flags

- `--json` — Structured output for parsing. Always use this.
- `--yes` — Skip confirmation prompts. Required for automated trades.
- `--quote` — Preview a trade without executing. Use before real trades.

## Error Handling

All `--json` responses return `{ "error": "message", "suggestion": "hint" }` on failure. Always check for the `error` field before processing results.

## Common Response Shapes

**`zora balance --json`** returns:

```json
{
  "wallet": [{ "name", "symbol", "address", "balance", "priceUsd", "usdValue" }],
  "coins":  [{ "rank", "name", "symbol", "address", "coinType", "creatorHandle", "balance", "usdValue", "priceUsd", "marketCap", "volume24h", ... }]
}
```

For "spendable ETH", read the `wallet` entry where `symbol === "ETH"`. The `coins` array holds the user's coin positions.

**`zora get <address-or-name> --json`** returns either:

- A single coin object: `{ "name", "address", "coinType", "marketCap", "uniqueHolders", "createdAt", "creatorHandle", "priceHistory", ... }` — when the input resolves uniquely. `priceHistory` may be `null` when no price data is available.
- An error: `{ "error": "Multiple coins match \"<name>\"...", "suggestion": "Use: zora get creator-coin <name> or zora get trend <name>" }` — when a name resolves to multiple coin types

Prefer addresses (`0x...`) over names to guarantee single-match behavior. For named lookups, fall back to typed forms like `zora get creator-coin <name>` or `zora get trend <name>` when the disambiguation error appears.

**`zora profile holdings <handle> --json`** returns: `{ "holdings": [{ "rank", "name", "symbol", "coinType", "address", "balance", "usdValue", "priceUsd", "marketCap" }], "pageInfo": { "hasNextPage", "endCursor" } }`

Sort options: `--sort usd-value | balance | market-cap | price-change` (no recency sort exists — use `profile trades` to derive that).

**`zora profile posts <handle> --json`** returns: `{ "posts": [{ "rank", "name", "symbol", "coinType", "address", "marketCap", "marketCapDelta24h", "volume24h", "createdAt" }], "pageInfo": { "hasNextPage", "endCursor" } }`

**`zora profile trades <handle> --json`** returns: `{ "trades": [{ "rank", "side": "BUY"|"SELL", "coinName", "coinSymbol", "coinType", "coinAddress", "coinAmount", "amountUsd", "transactionHash", "timestamp" }], "pageInfo": { "hasNextPage", "endCursor" } }`

Trades are returned **most-recent-first** (sorted by `timestamp` descending).

All three subcommands accept `--limit <n>` (max 20) and `--after <cursor>` for pagination.

## State Files

Each skill runs **one iteration per invocation** and persists state to a JSON file in the working directory. The presence of a skill's state file is how the skill decides between Setup Mode (first run) and Iteration Mode (subsequent runs).

State files:

- `.copy-trader-state.json`
- `.early-buyer-state.json`
- `.take-profit-state.json`
- `.watchlist-state.json`

Add these patterns to `.gitignore` to avoid committing them.

To reset a skill's config, delete its state file and re-invoke the skill.

## Scheduling

Skills are designed to be agent-agnostic: each invocation runs one iteration, then exits. To poll on a schedule, use whatever mechanism the hosting agent provides.

- **Claude Code** — pair with the `/loop` command:
  ```
  /loop 30m /copy-trader
  ```
- **Cursor / Windsurf** — use the agent's scheduled task feature (or a cron job that re-invokes the skill prompt)
- **Cron / shell script** — write a cron entry that invokes the skill's underlying CLI calls directly using the skill markdown as a reference
- **Manual** — just re-invoke the skill (e.g., `/copy-trader`) whenever you want the next cycle

Pick the interval based on the skill:

| Skill          | Suggested interval |
| -------------- | ------------------ |
| `/copy-trader` | 30m                |
| `/early-buyer` | 10m                |
| `/watchlist`   | 30m                |
| `/take-profit` | 15m                |

Shorter intervals catch changes faster but cost more API requests and potentially more gas. Longer intervals save cost but may miss short-lived movement.
