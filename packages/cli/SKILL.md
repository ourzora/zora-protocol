# Zora CLI Skill

You have access to the Zora CLI (`npx @zoralabs/cli`) for interacting with the Zora protocol on Base.
All commands support `--json` for structured output. Always use `--json` for parsing responses.
Trade commands require `--yes` to skip confirmation prompts.

## Environment Variables

- `ZORA_PRIVATE_KEY` — Wallet private key (hex, with or without 0x prefix)
- `ZORA_API_KEY` — API key for higher rate limits (get one at zora.co/settings/developer)

## Read Commands (no wallet needed)

### Browse coins

```bash
npx @zoralabs/cli explore --json --sort <sort> --type <type> --limit <n>
```

Sort: mcap, volume, new, gainers, last-traded, last-traded-unique, trending, featured
Type: all, creator-coin, post, trend
Returns: `{ "coins": [...], "nextCursor": "..." }`

### Look up a coin

```bash
npx @zoralabs/cli get <address-or-name> --json [--type creator-coin|post|trend]
```

Returns: `{ "name", "address", "coinType", "marketCap", "volume24h", "uniqueHolders", "createdAt", "creatorHandle" }`

### Price history

```bash
npx @zoralabs/cli price-history <address-or-name> --json --interval <1h|24h|1w|1m|ALL>
```

Returns: `{ "coin", "interval", "high", "low", "change", "prices": [{ "timestamp", "price" }] }`

### Creator/user profile

```bash
npx @zoralabs/cli profile <handle-or-address> --json
```

Returns: `{ "posts": [{ "name", "address", "marketCap", "volume24h" }] }`

### Auth status

```bash
npx @zoralabs/cli auth status --json
```

Returns: `{ "authenticated": true/false, "key": "masked", "source": "path" }`

## Trade Commands (requires ZORA_PRIVATE_KEY)

### Buy a coin

```bash
npx @zoralabs/cli buy <address> --eth <amount> --json --yes
npx @zoralabs/cli buy <address> --usd <amount> --token usdc --json --yes
npx @zoralabs/cli buy <address> --percent <1-100> --json --yes
npx @zoralabs/cli buy <address> --all --token zora --json --yes
```

Use `--quote` to preview without executing.
Returns: `{ "action": "trade", "coin", "received", "txHash", "explorerUrl" }`

### Sell a coin

```bash
npx @zoralabs/cli sell <address> --all --json --yes
npx @zoralabs/cli sell <address> --percent 50 --json --yes
npx @zoralabs/cli sell <address> --amount <n> --to usdc --json --yes
```

Returns: `{ "action": "trade", "coin", "soldAmount", "received", "txHash" }`

### Send tokens

```bash
npx @zoralabs/cli send eth --to <address> --amount <n> --json --yes
npx @zoralabs/cli send usdc --to <address> --amount <n> --json --yes
npx @zoralabs/cli send <coin-address> --to <address> --all --json --yes
```

Returns: `{ "action": "send", "asset", "amount", "to", "txHash" }`

### Check balances

```bash
npx @zoralabs/cli balance --json
```

Returns: `{ "spendable": [{ "token", "balance", "valueUsd" }], "coins": [{ "name", "balance", "valueUsd" }] }`

### Wallet info

```bash
npx @zoralabs/cli wallet info --json
```

Returns: `{ "address": "0x...", "source": "path" }`

## Error Handling

All errors in --json mode return: `{ "error": "message", "suggestion": "hint" }`
Always check for the `error` field before processing results.

## Coin Types

- `creator-coin` — A creator's personal token (look up by handle: `get jacob --type creator-coin`)
- `post` — A coin created from a post/content
- `trend` — A trend topic coin (look up by ticker: `get zora --type trend`)

When looking up by name, use `--type` to disambiguate.
When looking up by address (0x...), the type is resolved automatically.
