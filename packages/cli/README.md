# Zora CLI

> **Beta** — This package is in pre-release. Commands, flags, and output formats may change between versions without notice.

A command-line tool for interacting with the [Zora](https://zora.co) protocol. Explore coins, check prices, manage wallets, and trade — all from the terminal.

## Install

Requires **Node.js 20+**.

```bash
npm install -g @zoralabs/cli
```

## Quick start

```bash
# Guided first-time setup — wallet, API key, and deposit instructions
zora setup

# Browse trending coins
zora explore

# Look up a specific coin
zora get <address-or-name>

# Check price history
zora price-history <address-or-name>
```

## Commands

All commands support `--json` for machine-readable output. Commands with live data (`explore`, `balance`, `profile`) also support `--live` (interactive, default) and `--static` (snapshot). Use `--refresh <seconds>` to set the auto-refresh interval in `--live` mode.

| Command         | Description                                               | Wallet required |
| --------------- | --------------------------------------------------------- | --------------- |
| `setup`         | Guided first-time setup (wallet + API key + deposit info) | —               |
| `explore`       | Browse top, new, and highest volume coins                 | No              |
| `get`           | Look up a coin by address or name                         | No              |
| `price-history` | Display price history for a coin                          | No              |
| `auth`          | Configure or check API key status                         | No              |
| `profile`       | View creator or user profiles                             | No              |
| `buy`           | Buy a coin                                                | Yes             |
| `sell`          | Sell a coin                                               | Yes             |
| `balance`       | Show wallet balances (ETH, USDC, ZORA) and coin positions | Yes             |
| `wallet`        | Show wallet address, export key, or configure wallet      | Yes             |
| `send`          | Send tokens to another address                            | Yes             |

Run `zora --help` or `zora <command> --help` for detailed usage.

## Setup

`zora setup` walks through three steps: wallet configuration, API key (optional), and deposit instructions. It is re-runnable — existing configuration is detected and can be kept or overwritten.

```bash
zora setup            # interactive 3-step flow
zora setup --create   # skip wallet prompt, generate a new key
zora setup --yes      # non-interactive, accept all defaults
zora setup --force    # overwrite existing wallet and API key
```

The private key is stored locally at `~/.config/zora/wallet.json` with restricted permissions. `ZORA_PRIVATE_KEY` and `ZORA_API_KEY` environment variables take precedence over saved config files.

### Advanced

To configure wallet or API key individually (without running the full setup flow). All commands work without an API key but may be rate-limited. An API key also provides more accurate coin valuations in `zora balance` by using the SDK's liquidity-aware pricing:

- `zora wallet configure` — create or import a wallet (`--create`, `--force`)
- `zora auth configure` — save an API key; `zora auth status` — check current config

## Documentation

Full documentation is available at [cli.zora.com](https://cli.zora.com/).

## Feedback

Reach out at [x.com/zorasupport](https://x.com/zorasupport) or [support.zora.co](https://support.zora.co).
