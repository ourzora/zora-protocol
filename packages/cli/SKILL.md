# Zora CLI Skill

You have access to the Zora CLI (`npx @zoralabs/cli`) for interacting with the Zora protocol. All operations run on **Base mainnet** — ETH, USDC, and ZORA tokens must be on Base (not Ethereum mainnet or other chains).

## Quick Start

1. **Create a wallet:**
   ```bash
   npx @zoralabs/cli setup --create --yes --json
   ```
2. **Fund it:** Send ETH on Base to the wallet address returned above.
3. **Browse top coins:**
   ```bash
   npx @zoralabs/cli explore --sort trending --type all --json
   ```
4. **Buy a coin** using the `address` from the explore results:
   ```bash
   npx @zoralabs/cli buy 0x<address> --eth 0.01 --yes --json
   ```

## Setup

### Wallet creation and import

Create a new wallet:

```bash
npx @zoralabs/cli setup --create --yes --json
```

Or import an existing private key (interactive — omit `--yes`):

```bash
npx @zoralabs/cli setup --json
```

Use `--force` to overwrite an existing wallet.

Returns:

```json
{
  "wallet": {
    "action": "created",
    "address": "0x...",
    "path": "/path/to/wallet.json"
  },
  "apiKey": "saved"
}
```

`wallet.action` values: `"created"`, `"imported"`, `"env_detected"` (using ZORA_PRIVATE_KEY), `"skipped"` (includes a `warning` field). `path` is only present for `"created"` and `"imported"`.

`apiKey` values: `"saved"`, `"skipped"`, `"env_override"` (using ZORA_API_KEY env var), `"already_set"`.

After creating or importing, fund the wallet by sending ETH on Base to the returned address. ETH is needed for gas and as the default token for buying coins.

### API key (optional)

Get one at zora.co/settings/developer. Unlocks higher rate limits and more accurate coin valuations in `balance` but is not required — all commands work without one. The `setup` command prompts for an API key after wallet configuration.

### Environment Variables

- `ZORA_PRIVATE_KEY` — Wallet private key (hex, with or without 0x prefix). If set, the CLI uses this instead of the saved wallet.
- `ZORA_API_KEY` — API key for higher rate limits and more accurate coin valuations in `balance`.

### Auth status

```bash
npx @zoralabs/cli auth status --json
```

Returns:

```json
{ "authenticated": false }
```

When authenticated:

```json
{
  "authenticated": true,
  "key": "zora_****...****",
  "source": "/path/to/config.json"
}
```

### Wallet info

```bash
npx @zoralabs/cli wallet info --json
```

Returns:

```json
{ "address": "0x1234...5678", "source": "/path/to/wallet.json" }
```

## Structured Output

**Always use `--json` on every command.** This gives structured JSON output suitable for parsing. Without it, the CLI returns human-readable text.

## Error Handling

All errors in `--json` mode return: `{ "error": "message" }` with an optional `"suggestion"` field.
Always check for the `error` field before processing results.

## Coin Types

- `creator-coin` — A creator's personal token (look up by handle: `get creator-coin jacob`)
- `post` — A coin created from a post/content
- `trend` — A trend topic coin (look up by ticker: `get trend zora`)

When looking up by name, use the type prefix to disambiguate.
When looking up by address (0x...), the type is resolved automatically.

## Confirmation Prompts

Some commands require interactive confirmation before executing. Use `--yes` to skip these prompts for fully autonomous operation. If working with a human, you may want to omit `--yes` so the user can review and confirm.

Commands that prompt for confirmation without `--yes`:

- `buy` — confirms trade details before executing
- `sell` — confirms trade details before executing
- `send` — confirms transfer details before executing
- `setup` — prompts for wallet creation method and API key
- `auth` — prompts during authentication flow
- `wallet` — prompts during wallet operations (export, delete)

## Pagination

The `explore` and `balance coins` commands support cursor-based pagination.

- `--limit <1-20>` — results per page (default 10, max 20)
- `--after <cursor>` — fetch the next page by passing the `endCursor` from the previous response

Paginated responses include a `pageInfo` object:

```json
{ "pageInfo": { "endCursor": "abc123", "hasNextPage": true } }
```

When `hasNextPage` is `true`, pass `--after <endCursor>` to get the next page.

## Read Commands (no wallet needed)

### Browse coins

```bash
npx @zoralabs/cli explore --json --sort <sort> --type <type> --limit <n>
```

Sort: mcap (default), volume, new, trending, featured
Type: creator-coin (default), all, post, trend

> **Note:** `--sort featured` only supports `--type creator-coin` and `--type post`.

Returns:

```json
{
  "coins": [
    {
      "name": "jacob",
      "address": "0x1234...5678",
      "coinType": "creator-coin",
      "symbol": "jacob",
      "creatorAddress": "0xabcd...ef01",
      "creatorHandle": "jacob",
      "priceUsd": 0.12,
      "marketCap": 50000,
      "marketCapDelta24h": 5000,
      "volume24h": 12000,
      "totalVolume": 100000,
      "uniqueHolders": 350,
      "createdAt": "2025-01-15T10:30:00Z"
    }
  ],
  "pageInfo": { "endCursor": "abc123", "hasNextPage": true }
}
```

### Look up a coin

```bash
npx @zoralabs/cli get 0x<address> --json
npx @zoralabs/cli get <name> --json
npx @zoralabs/cli get creator-coin <name> --json
npx @zoralabs/cli get trend <ticker> --json
```

- **Address:** `get 0x1234...` — always unambiguous, works for any coin type
- **Bare name:** `get jacob` — tries both creator-coin and trend; if ambiguous, returns `{ "matches": [...], "hint": "..." }` instead of a single coin — use a typed form to disambiguate
- **Typed name:** `get creator-coin jacob` or `get trend zora` — disambiguates when using a name

Returns:

```json
{
  "name": "jacob",
  "address": "0x1234...5678",
  "coinType": "creator-coin",
  "marketCap": "50000",
  "marketCapDelta24h": "5000",
  "volume24h": "12000",
  "uniqueHolders": 350,
  "createdAt": "2025-01-15T10:30:00Z",
  "creatorAddress": "0xabcd...ef01",
  "creatorHandle": "jacob"
}
```

### Explore → Get mapping

To look up a coin from explore results, use its `address` field:

```bash
# 1. Browse trending coins
npx @zoralabs/cli explore --sort trending --type all --json
# 2. Pick a coin from the results and pass its address to get
npx @zoralabs/cli get 0x<address-from-explore> --json
```

Alternatively, use the `coinType` from explore to build a typed lookup: `get creator-coin <creatorHandle>` or `get trend <symbol>`.

### Price history

```bash
npx @zoralabs/cli price-history <address-or-name> --json --interval <1h|24h|1w|1m|ALL>
```

Default interval: `1w`

Returns:

```json
{
  "coin": "jacob",
  "type": "creator-coin",
  "interval": "1w",
  "high": 0.00523,
  "low": 0.00412,
  "change": 0.023,
  "prices": [
    { "timestamp": "2025-01-01T00:00:00Z", "price": 0.00512 },
    { "timestamp": "2025-01-02T00:00:00Z", "price": 0.00523 }
  ]
}
```

`change` is `null` when the first price in the interval is 0.

### Creator/user profile

If no identifier is provided, defaults to the current wallet's profile.

To view a profile's holdings:

```bash
npx @zoralabs/cli profile holdings [handle-or-address] --json --sort <sort> --limit <n> --after <cursor>
```

Holdings sort: usd-value (default), balance, market-cap, price-change

```json
{
  "holdings": [
    {
      "rank": 1,
      "name": "jacob",
      "symbol": "jacob",
      "coinType": "CREATOR",
      "address": "0xabcd...ef01",
      "balance": "1000.5",
      "usdValue": 250.15,
      "priceUsd": 0.25,
      "marketCap": 5000000
    }
  ],
  "pageInfo": { "endCursor": "abc123", "hasNextPage": true }
}
```

To view a profile's posts:

```bash
npx @zoralabs/cli profile posts [handle-or-address] --json --limit <n> --after <cursor>
```

```json
{
  "posts": [
    {
      "rank": 1,
      "name": "My Post",
      "symbol": "POST",
      "coinType": "post",
      "address": "0x1234...5678",
      "marketCap": "50000",
      "marketCapDelta24h": "5000",
      "volume24h": "12000",
      "createdAt": "2025-01-15T10:30:00Z"
    }
  ],
  "pageInfo": { "endCursor": "abc123", "hasNextPage": true }
}
```

To view a profile's trade activity (buys and sells):

```bash
npx @zoralabs/cli profile trades [handle-or-address] --json --limit <n> --after <cursor>
```

```json
{
  "trades": [
    {
      "rank": 1,
      "side": "BUY",
      "coinName": "jacob",
      "coinSymbol": "jacob",
      "coinType": "CREATOR",
      "coinAddress": "0x1234...5678",
      "coinAmount": "1000500000000000000000",
      "amountUsd": "25.50",
      "transactionHash": "0xabcd...ef01",
      "timestamp": "2025-01-15T10:30:00Z"
    }
  ],
  "pageInfo": { "endCursor": "abc123", "hasNextPage": true }
}
```

For a quick overview without pagination, `profile` returns posts, holdings, and trades in a single call:

```bash
npx @zoralabs/cli profile [handle-or-address] --json
```

This doesn't support pagination, so use the individual `profile posts`, `profile holdings`, and `profile trades` commands when you need to page through results.

## Trading & Wallet Operations (requires wallet)

You can identify coins by address, by typed name (`buy creator-coin jacob`, `buy trend zora`), or by bare name. Using a typed name or address is preferred to avoid ambiguity.

**All trade and send commands wait for on-chain confirmation before returning.** When you receive a response with a `tx` hash, the transaction is confirmed on-chain. However, read commands (`balance`, `get`, `explore`) use the API which may take a few seconds to index the new state.

### Gas reserve

When using `--all` or `--percent` with ETH, the CLI reserves **0.00001 ETH** for gas — it will error if the balance is at or below this reserve. This applies to buy, sell, and send. It does not apply to USDC or ZORA tokens.

### Buy

Every command requires exactly one amount flag — the CLI will error if none is provided or if more than one is given.

```bash
npx @zoralabs/cli buy <identifier> --eth <amount> --json --yes
npx @zoralabs/cli buy <identifier> --usd <amount> --json --yes
npx @zoralabs/cli buy <identifier> --percent <1-100> --json --yes
npx @zoralabs/cli buy <identifier> --all --json --yes
```

Amount flags: `--eth <n>`, `--usd <n>`, `--percent <1-100>`, `--all`

Other flags:

- `--token <eth|usdc|zora>` — which token to spend (default `eth`)
- `--slippage <0-99>` — slippage tolerance (default 1%)
- `--quote` — dry-run / preview the trade without executing

Returns:

```json
{
  "action": "buy",
  "coin": "jacob",
  "address": "0x1234...5678",
  "spent": { "amount": "0.01", "raw": "10000000000000000", "symbol": "ETH" },
  "received": {
    "amount": "1000.5",
    "raw": "1000500000000000000000",
    "symbol": "jacob"
  },
  "tx": "0xabcd...ef01"
}
```

**Buy `--quote` response:**

```json
{
  "action": "quote",
  "coin": "jacob",
  "address": "0x1234...5678",
  "spend": { "amount": "0.01", "raw": "10000000000000000", "symbol": "ETH" },
  "estimated": {
    "amount": "1000.5",
    "raw": "1000500000000000000000",
    "symbol": "jacob"
  },
  "slippage": 1
}
```

### Sell

Every command requires exactly one amount flag — the CLI will error if none is provided or if more than one is given.

```bash
npx @zoralabs/cli sell <identifier> --all --json --yes
npx @zoralabs/cli sell <identifier> --percent 50 --json --yes
npx @zoralabs/cli sell <identifier> --usd <amount> --json --yes
npx @zoralabs/cli sell <identifier> --amount <n> --json --yes
```

Amount flags: `--usd <n>`, `--percent <1-100>`, `--all`, `--amount <n>` (specific token quantity)

Other flags:

- `--to <eth|usdc|zora>` — which token to receive (default `eth`)
- `--slippage <0-99>` — slippage tolerance (default 1%)
- `--quote` — dry-run / preview the trade without executing

The sell command validates your token balance before submitting — it will error early if you have zero balance. No need to check manually.

Returns:

```json
{
  "action": "sell",
  "coin": "jacob",
  "address": "0x1234...5678",
  "sold": {
    "amount": "500.25",
    "raw": "500250000000000000000",
    "symbol": "jacob"
  },
  "received": {
    "amount": "0.25",
    "raw": "250000000000000000",
    "symbol": "ETH",
    "source": "receipt"
  },
  "tx": "0xabcd...ef01"
}
```

**Sell `--quote` response:**

```json
{
  "action": "quote",
  "coin": "jacob",
  "address": "0x1234...5678",
  "sell": {
    "amount": "1000.5",
    "raw": "1000500000000000000000",
    "symbol": "jacob"
  },
  "estimated": {
    "amount": "0.01",
    "raw": "10000000000000000",
    "symbol": "ETH"
  },
  "slippage": 1
}
```

### Send tokens

Every command requires exactly one amount flag — the CLI will error if none is provided or if more than one is given.

```bash
npx @zoralabs/cli send eth --to <address> --amount <n> --json --yes
npx @zoralabs/cli send usdc --to <address> --amount <n> --json --yes
npx @zoralabs/cli send zora --to <address> --amount <n> --json --yes
npx @zoralabs/cli send <coin-address> --to <address> --all --json --yes
npx @zoralabs/cli send creator-coin <name> --to <address> --all --json --yes
npx @zoralabs/cli send trend <ticker> --to <address> --all --json --yes
```

Amount flags: `--percent <1-100>`, `--all`, `--amount <n>` (specific token quantity)

Returns:

```json
{
  "action": "send",
  "coin": "ETH",
  "address": null,
  "sent": {
    "amount": "0.5",
    "raw": "500000000000000000",
    "symbol": "ETH",
    "amountUsd": 1750.0
  },
  "to": "0xabcd...ef01",
  "tx": "0x9876...5432"
}
```

`sent.amountUsd` is `null` when the USD price lookup fails.

### Check balances

```bash
npx @zoralabs/cli balance --json
npx @zoralabs/cli balance spendable --json
npx @zoralabs/cli balance coins --json --sort <sort> --limit <n> --after <cursor>
```

- `balance` — shows both wallet tokens and coin holdings
- `balance spendable` — shows only ETH, USDC, ZORA balances
- `balance coins` — shows coin holdings (supports pagination and sorting)
  - Sort: usd-value (default), balance, market-cap, price-change

`balance` returns both `wallet` and `coins`:

```json
{
  "wallet": [
    {
      "name": "Ether",
      "symbol": "ETH",
      "address": null,
      "balance": "1.5",
      "priceUsd": 3500.5,
      "usdValue": 5250.75
    },
    {
      "name": "USD Coin",
      "symbol": "USDC",
      "address": "0xa0b8...eb48",
      "balance": "1000.00",
      "priceUsd": 1.0,
      "usdValue": 1000.0
    },
    {
      "name": "ZORA",
      "symbol": "ZORA",
      "address": "0x7122...037f",
      "balance": "500.5",
      "priceUsd": 2.35,
      "usdValue": 1176.18
    }
  ],
  "coins": [
    {
      "rank": 1,
      "name": "jacob",
      "symbol": "jacob",
      "type": "creator-coin",
      "coinType": "CREATOR",
      "address": "0x1234...5678",
      "balance": "1000.5",
      "usdValue": 250.15,
      "priceUsd": 0.25,
      "marketCap": 5000000,
      "marketCapDelta24h": 50000,
      "volume24h": 250000
    }
  ]
}
```

> **Note:** Balance coins emit both `type` (formatted: "creator-coin", "post", "trend") and `coinType` (raw: "CREATOR", "CONTENT", "TREND"). Profile holdings only emit `coinType` (raw).

`balance spendable` returns only the `wallet` array (same shape as above, without `coins`).

`balance coins` returns only the `coins` array with pagination:

```json
{
  "coins": [
    {
      "rank": 1,
      "name": "jacob",
      "symbol": "jacob",
      "type": "creator-coin",
      "coinType": "CREATOR",
      "address": "0x1234...5678",
      "balance": "1000.5",
      "usdValue": 250.15,
      "priceUsd": 0.25,
      "marketCap": 5000000,
      "marketCapDelta24h": 50000,
      "volume24h": 250000
    }
  ],
  "pageInfo": { "endCursor": "abc123", "hasNextPage": true }
}
```

## Workflow Examples

### First trade (discovery → buy)

```bash
# 1. Browse trending coins
npx @zoralabs/cli explore --sort trending --type all --json
# 2. Get details on one you like
npx @zoralabs/cli get 0x<address> --json
# 3. Check the price you'd pay
npx @zoralabs/cli buy 0x<address> --eth 0.01 --quote --json
# 4. Execute the trade
npx @zoralabs/cli buy 0x<address> --eth 0.01 --yes --json
```

### Taking profit

```bash
# 1. Check what you hold
npx @zoralabs/cli balance --json
# 2. Sell half of a position
npx @zoralabs/cli sell 0x<address> --percent 50 --yes --json
```

### Monitoring a coin

```bash
# 1. Get current state
npx @zoralabs/cli get 0x<address> --json
# 2. Check price history
npx @zoralabs/cli price-history 0x<address> --interval 24h --json
# 3. Check who's creating coins
npx @zoralabs/cli profile <handle> --json
```
