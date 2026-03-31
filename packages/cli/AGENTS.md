# Zora CLI

Developer CLI tool for interacting with the Zora platform. Package: `@zoralabs/cli` (will be published on npm as `npx @zoralabs/cli`, with Brew distribution planned via standalone binary).

## Tech stack

- **TypeScript** with `tsup` for bundling (ESM, Node 20+)
- **Commander** for CLI framework (arg parsing, subcommands, auto help)
- **Ink** (React for terminals) for rendering table output, spinners, and styled text
- **React 19** — peer dependency for Ink 6
- **@zoralabs/coins-sdk** for querying the Zora UAPI (handles auth, persisted queries)
- **vitest** for unit tests
- **tsx** for dev (runs TypeScript directly, no build step)

## How to run locally

The CLI depends on `@zoralabs/coins-sdk` and other TypeScript packages in the monorepo. These must be built before running or testing the CLI.

From the repo root:

```bash
pnpm install            # install dependencies
pnpm build:js           # build all TS packages — required before running or testing the CLI
```

Without `pnpm build:js`, both `pnpm zora` and `pnpm test` will fail with `ERR_MODULE_NOT_FOUND` for `@zoralabs/coins-sdk`.

Once built:

```bash
cd packages/cli
pnpm zora                              # run cli (--help for all commands)
pnpm zora explore --type creator-coin  # args pass directly (no -- needed)
pnpm test                              # run unit tests
pnpm build                             # production build to dist/
```

## Project structure

```
packages/cli/
├── src/
│   ├── index.tsx      # entry point, registers commands
│   ├── commands/      # one file per CLI command (auth, balance, buy, sell, explore, get, price-history, profile, send, setup, wallet)
│   ├── components/    # Ink (React) components for terminal UI (tables, coin detail, zorb art)
│   ├── lib/           # shared utilities (formatting, config, wallet, output helpers, coin resolution)
│   └── test/          # vitest global setup and test helpers
├── tsconfig.json      # includes "jsx": "react-jsx"
├── vitest.config.ts   # sets NODE_ENV for react-reconciler compat
├── tsup.config.ts     # bundles to dist/index.js with node shebang
└── .npmrc             # reporter=silent (suppresses pnpm script banners)
```

## Commands

All commands support `--json` (global flag) for machine-readable output. Commands with live data (explore, balance, profile) also support `--live` (interactive, default) and `--static` (snapshot). These three flags are mutually exclusive.

| Command         | Description                                               | Wallet required |
| --------------- | --------------------------------------------------------- | --------------- |
| `setup`         | Guided first-time setup (wallet + API key + deposit info) | —               |
| `explore`       | Browse top, new, and highest volume coins                 | No              |
| `get`           | Look up a coin by address or name                         | No              |
| `price-history` | Display price history for a coin                          | No              |
| `auth`          | Configure or check API key status                         | No              |
| `buy`           | Buy a coin                                                | Yes             |
| `sell`          | Sell a coin                                               | Yes             |
| `balance`       | Show wallet balances (ETH, USDC, ZORA) and coin positions | Yes             |
| `send`          | Send tokens to another address                            | Yes             |
| `wallet`        | Show wallet address, export key, or configure wallet      | Yes             |
| `profile`       | View creator or user profiles                             | No              |

## Setup

`zora setup` is a guided 3-step flow: wallet configuration, API key (optional), and deposit instructions. It is re-runnable — existing configuration is detected and can be kept or overwritten.

- `zora setup` — interactive 3-step flow
- `zora setup --create` — skip wallet prompt, generate a new key
- `zora setup --yes` — non-interactive, accept all defaults
- `zora setup --force` — overwrite existing wallet and API key

The private key is saved to `~/.config/zora/wallet.json` (0600 perms). **Never delete or modify this file** — it contains the only copy of the wallet's private key. Loss means loss of funds.

`ZORA_PRIVATE_KEY` and `ZORA_API_KEY` env vars take precedence over saved config files.

### Advanced

To configure wallet or API key individually (without running the full setup flow):

- `zora wallet configure` — create or import a wallet (`--create`, `--force`)
- `zora auth configure` — save an API key; `zora auth status` — check current config

**API key is optional** — all commands work without one, but requests may be rate-limited.

## SDK patterns

- `--json` is a global flag — when present, commands output structured JSON instead of styled terminal output. Use `getJson(this)` from `src/lib/output.ts` to check it, and `outputData` to handle both paths.
- `--live` and `--static` are per-command flags on explore, balance, and profile. They control presentation mode (interactive vs snapshot). Use `getOutputMode(this, "live")` then pass the result to `getLiveConfig(this, output)` from `src/lib/output.ts`. `--refresh <seconds>` is also per-command and sets the auto-refresh interval for `--live` mode (min 5s, default 30s).
- `--json`, `--live`, and `--static` are mutually exclusive — `getOutputMode()` validates this.
- SDK query functions return `{ error, data }` — always check `error` first
- Coin resolution (`src/lib/coin-ref.ts`): `parseCoinRef` parses identifiers, `resolveCoin` does the async SDK lookup
- Not all explore sort/type combos are valid — the CLI errors with supported options if an invalid combo is used
- `ZORA_API_TARGET` env var overrides the SDK base URL (useful for local dev or staging)

## Building a standalone binary

Build a self-contained executable (no Node.js required) using `bun build --compile`:

```bash
cd packages/cli
pnpm run build:binary         # build for current platform → ./bin/zora
./bin/zora --help              # run it
```

Cross-compile for other platforms:

```bash
pnpm run build:binary:all          # builds all five targets below
pnpm run build:binary:mac-arm64    # → ./bin/zora-darwin-arm64
pnpm run build:binary:mac-x64     # → ./bin/zora-darwin-x64
pnpm run build:binary:linux-x64   # → ./bin/zora-linux-x64
pnpm run build:binary:linux-arm64 # → ./bin/zora-linux-arm64
pnpm run build:binary:windows-x64 # → ./bin/zora-windows-x64.exe
```

The `bin/` directory is gitignored. Requires `bun` to be installed (`npm install -g bun`).
