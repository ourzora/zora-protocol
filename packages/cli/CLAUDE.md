# Zora CLI

Developer CLI tool for interacting with the Zora platform. Package: `@zoralabs/cli`.

## Tech stack

- **TypeScript** with `tsup` for bundling (ESM, Node 24+)
- **Commander** for CLI framework (arg parsing, subcommands, auto help)
- **Ink** (React for terminals) for rendering table output, spinners, and styled text
- **React 19** — peer dependency for Ink 6
- **@inquirer/password** for secure API key input (no echo)
- **date-fns** for date formatting (relative time via `formatDistanceStrict`, absolute via `format`)
- **@zoralabs/coins-sdk** for querying the Zora UAPI (handles auth, persisted queries)
- **vitest** for unit tests
- **ink-testing-library** for component tests (`render()` → `lastFrame()`)
- **tsx** for dev (runs TypeScript directly, no build step)
- Located at `packages/cli/` within the monorepo

## How to run locally

```bash
cd packages/cli
pnpm install
pnpm zora auth configure  # set API key
pnpm zora auth status  # check auth
pnpm zora --help       # show help
pnpm zora --version    # show version
pnpm dev              # watch mode (rebuilds on change)
pnpm test             # run unit tests
pnpm build            # production build to dist/
```

Note: `pnpm zora` uses tsx — pass args directly (no `--` needed).

## Project structure

```
packages/cli/
├── src/
│   ├── index.ts              # entry point, registers commands
│   ├── commands/
│   │   ├── auth.ts           # auth configure/status commands
│   │   ├── buy.ts            # buy command (trade ETH for coins)
│   │   ├── explore.tsx       # explore command (browse coins, uses JSX for table rendering)
│   │   ├── get.tsx           # get command (look up single coin)
│   │   ├── setup.ts          # wallet setup (generate or import private key)
│   │   └── wallet.ts         # wallet info command
│   ├── components/
│   │   ├── CoinDetail.tsx    # Ink component: single coin detail view (get command)
│   │   ├── ExploreView.tsx   # Ink component: loading → table → exit lifecycle
│   │   └── table.tsx         # reusable generic typed Ink table component
│   ├── lib/
│   │   ├── coin-ref.ts       # coin resolution: parseCoinRef, resolveCoin
│   │   ├── config.ts         # read/write ~/.config/zora/config.json
│   │   ├── format.ts         # pure formatting: currency, change %, truncation, date/time (date-fns)
│   │   ├── mask-key.ts       # redact API keys for display
│   │   ├── output.ts         # unified output helpers (outputJson, outputErrorAndExit, outputData)
│   │   ├── prompt.ts         # prompt wrappers respecting --yes for non-interactive usage
│   │   ├── render.tsx        # thin Ink renderOnce wrapper
│   │   └── types.ts          # shared types (CoinType, SortOption, TypeOption, CoinNode)
│   └── test/
│       ├── create-program.ts # test helper for optsWithGlobals()
│       └── setup.ts          # vitest global setup (temp homedir, module reset)
├── package.json
├── tsconfig.json             # includes "jsx": "react-jsx"
├── vitest.config.ts          # sets NODE_ENV for react-reconciler compat
├── tsup.config.ts            # bundles to dist/index.js with node shebang
└── .npmrc                    # reporter=silent (suppresses pnpm script banners)
```

## Key decisions

- **commander** over oclif/yargs — lightweight, auto-generates help, widely used
- **tsup** for build — ESM output with shebang, fast (Ink components are lazily loaded via dynamic import)
- **Part of the monorepo** — shares workspace tooling and dependencies
- **ESM** format output targeting Node 24+
- Version inlined at build time via tsup `define` (falls back to package.json in dev)
- Will be published as `@zoralabs/cli` on npm (runnable via `npx @zoralabs/cli`)
- Brew distribution planned for later (via standalone binary)

## Auth

- **API key is optional** — the SDK uses registered queries accessible without a key (see [SDK docs](https://docs.zora.co/coins/sdk))
- Without a key: read-only commands (e.g. `explore`) work, but requests are subject to rate limiting
- With a key: significantly higher rate limits; required for future write operations (e.g. uploading metadata)
- The SDK passes the key as an `api-key` header when set; when unset, `getApiKeyMeta()` returns `{}` (see `node_modules/@zoralabs/coins-sdk/src/api/api-key.ts`)
- Rate limiting is enforced server-side — the SDK has no client-side retry/backoff logic
- Get an API key from: https://zora.co/settings/developer
- Config stored at `~/.config/zora/config.json` (0600 perms)
- `ZORA_API_KEY` env var takes precedence over config file
- `zora auth configure` — prompts for API key (input is muted, not echoed); overwrites existing key
- `zora auth status` — shows masked key and source, or notes that the CLI works without one
- Short keys (<=12 chars) are fully masked as `***`
- Use `getApiKey()` from `src/lib/config.ts` in any command — if it returns undefined, skip `setApiKey()` (SDK works without it)
- Use `getEnvApiKey()` to check if the env var is set (centralizes the empty-string guard)
- Filesystem errors during save are caught and shown as human-readable messages

## Explore command

- `zora explore` — browse coins with `--sort` (mcap, volume, new, gainers, last-traded, last-traded-unique, trending, featured), `--type` (all, trend, creator-coin, post), `--limit`, `--json`
- Defaults: `--sort mcap --type post` (most valuable posts)
- `--sort volume` is 24-hour volume, not all-time
- Not all sort/type combos are available — the CLI will error with supported types if you pick an invalid combo
- Uses `@zoralabs/coins-sdk` query functions
- SDK returns `{ error, data }` — always check `response.error` before accessing data (SDK does not throw on auth failure)
- 24h change is computed from `marketCapDelta24h` (absolute USD delta), not a percentage field
- `--limit` is validated client-side (1–20) because the server caps at 20
- `--json` is a boolean flag — present means JSON output, absent means table (default)
- **Table output uses Ink** — `explore.tsx` uses JSX with `renderOnce` to render a `TableComponent` inline for table output
- `ExploreView` shows a spinner while fetching, then renders a `TableComponent`, then calls `unmount()` to exit
- Pure formatting functions (`formatCompactCurrency`, `formatChange`) live in `explore.tsx`; `formatMcapChange` in `lib/format.ts` returns `{ text, color }` for declarative Ink rendering

### Supported sort/type combinations

| sort               | type         | SDK function                     |
| ------------------ | ------------ | -------------------------------- |
| mcap               | all          | `getMostValuableAll`             |
| mcap               | trend        | `getMostValuableTrends`          |
| mcap               | creator-coin | `getMostValuableCreatorCoins`    |
| mcap               | post         | `getCoinsMostValuable`           |
| volume             | all          | `getExploreTopVolumeAll24h`      |
| volume             | trend        | `getTopVolumeTrends24h`          |
| volume             | creator-coin | `getExploreTopVolumeCreators24h` |
| volume             | post         | `getCoinsTopVolume24h`           |
| new                | all          | `getExploreNewAll`               |
| new                | trend        | `getNewTrends`                   |
| new                | creator-coin | `getCreatorCoins`                |
| new                | post         | `getCoinsNew`                    |
| gainers            | post         | `getCoinsTopGainers`             |
| last-traded        | post         | `getCoinsLastTraded`             |
| last-traded-unique | post         | `getCoinsLastTradedUnique`       |
| trending           | all          | `getTrendingAll`                 |
| trending           | trend        | `getTrendingTrends`              |
| trending           | creator-coin | `getTrendingCreators`            |
| trending           | post         | `getTrendingPosts`               |
| featured           | creator-coin | `getExploreFeaturedCreators`     |
| featured           | post         | `getExploreFeaturedVideos`       |

## Get command

- `zora get <identifier>` — look up a coin by address (0x...) or creator name
- `--type creator-coin` — explicit creator-coin lookup (default for non-address identifiers)
- `--type` accepts `creator-coin`, `post`, `trend` — validated against `CoinType`
- `--type trend` — address lookup supported; name lookup not yet supported, errors for non-address identifiers
- `--type post` — name lookup not supported, gives "address-only" error for non-address identifiers
- When `--type` is provided, the resolved coin's type is validated against the requested type (e.g. `--type post` on a creator-coin address errors)
- `--json` (global flag) returns structured JSON with raw `createdAt` from API; table mode shows relative + absolute local time via date-fns
- Uses unified output helpers: `getJson(this)`, `outputErrorAndExit`, `outputData` (same pattern as explore)
- **Table output uses Ink** — `get.tsx` fetches in the handler, then uses `outputData` + `renderOnce(<CoinDetail>)` (same pattern as explore)
- `CoinDetail` is a purely presentational component — accepts a `ResolvedCoin` prop, renders vertical key-value table
- Creator row only shown for post coins, and only when handle or address is available
- No wallet required

### Coin resolution (`src/lib/coin-ref.ts`)

Shared coin lookup logic reusable by future commands (buy, sell, price-history):

- `parseCoinRef(identifier, type?)` — pure arg parsing into `CoinRef` discriminated union (address, prefixed, ambiguous)
- `resolveCoin(ref)` — async SDK calls returning `ResolveCoinResult` (found or not-found)
- Address resolution uses `getCoin({ address })` from the SDK
- Name resolution uses `getProfile({ identifier })` → `creatorCoin.address` → `getCoin`
- `coinType` is accessed via `(token as any).coinType` — present at runtime but not in SDK TypeScript types

### Test strategy

- `get.test.ts` tests the JSON output path only (mocks SDK, exercises Commander's `parseAsync`)
- `CoinDetail.test.tsx` tests the Ink component rendering (uses `ink-testing-library`)
- `coin-ref.test.ts` tests `parseCoinRef` (pure/sync) and `resolveCoin` (mocked SDK calls)
