# Zora CLI

> **Beta** — This package is in pre-release. Commands, flags, and output formats may change between versions without notice.

A command-line tool for interacting with the [Zora](https://zora.co) protocol. Explore coins, check prices, manage wallets, and trade — all from the terminal.

## Install

Requires **Node.js 24+**.

```bash
npm install -g @zoralabs/cli
```

## Quick start

```bash
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
| `explore`       | Browse top, new, and highest volume coins                 | No              |
| `get`           | Look up a coin by address or name                         | No              |
| `price-history` | Display price history for a coin                          | No              |
| `auth`          | Configure or check API key status                         | No              |
| `profile`       | View creator or user profiles                             | No              |
| `setup`         | Set up a wallet (generate or import private key)          | —               |
| `buy`           | Buy a coin                                                | Yes             |
| `sell`          | Sell a coin                                               | Yes             |
| `balance`       | Show wallet balances (ETH, USDC, ZORA) and coin positions | Yes             |
| `wallet`        | Show wallet address, storage location, or export key      | Yes             |
| `send`          | Send tokens to another address                            | Yes             |

Run `zora --help` or `zora <command> --help` for detailed usage.

## Wallet setup

Commands that sign transactions require a wallet. Set one up with:

```bash
zora setup            # interactive — create or import a key
zora setup --create   # generate a new key non-interactively
```

The private key is stored locally at `~/.config/zora/wallet.json` with restricted permissions. Alternatively, set the `ZORA_PRIVATE_KEY` environment variable.

## API key (optional)

Read-only commands work without an API key but may be rate-limited. To get a key, create an account at [zora.co](https://zora.co) and generate one at [zora.co/settings/developer](https://zora.co/settings/developer), then:

```bash
zora auth configure   # save the key
zora auth status      # check current config
```

The `ZORA_API_KEY` environment variable takes precedence over the saved config.

## Documentation

Full documentation is available at [docs.zora.co](https://docs.zora.co/).

## Feedback

Reach out at [x.com/zoradevs](https://x.com/zoradevs) or [warpcast/~/channel/zora-devs](https://warpcast.com/~/channel/zora-devs).
