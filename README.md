# Niche Protocol

[![Contracts](https://github.com/ourzora/zora-protocol/actions/workflows/contracts.yml/badge.svg)](https://github.com/ourzora/zora-protocol/actions/workflows/contracts.yml)

This repository is a monorepo for the Niche Protocol - a customized implementation of the Zora Protocol using the Niche coin as the backing currency for creator coins.

## Key Differences

- **Backing Currency**: Uses Niche coin (`0x5ab1a8dbb78c272540d3652dac9c46d9cbfcecbf`) instead of ZORA token
- **Branding**: Updated to "Niche" throughout documentation and UI
- **Creator Coins**: All creator coins are backed by Niche token instead of ZORA

In it you will find:

### Active Packages

- [Coins](./packages/coins)
- [Comments](./packages/comments)
- [Coins SDK](./packages/coins-sdk)
- [Protocol Deployments](./packages/protocol-deployments)
- [Smart Wallet](./packages/smart-wallet)

### Legacy Packages

- [Legacy Contracts](./legacy) - Contains legacy contract packages (1155-contracts, erc20z, sparks, cointags, protocol-sdk, etc.)

## Documentation

View the Niche documentation (deployed on branch `claude/niche-clanker-app-011CV492FfwRDh9PmXRaV3gm`)

**Niche Coin Details:**

- Contract Address: `0x5ab1a8dbb78c272540d3652dac9c46d9cbfcecbf`
- Network: Base (Chain ID: 8453)
- Token: Niche
- [View on Rainbow](https://rainbow.me/token/base/0x5ab1a8dbb78c272540d3652dac9c46d9cbfcecbf)

## Setup

Install prerequisites:

- [Node.js and pnpm](https://pnpm.io/installation)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

Install dependencies:

    pnpm install

## Build System

This repository uses an optimized build system with two distinct build modes:

### JavaScript/TypeScript Development (`build:js`)

For JavaScript/TypeScript development and wagmi consumption:

    pnpm build:js

This command:

- Builds only the JavaScript/TypeScript artifacts needed for client applications
- Generates wagmi-compatible type definitions and ABIs
- Skips full Solidity compilation for faster builds
- Is optimized for frontend developers and SDK usage

### Full Development (`build`)

For complete contract development and testing:

    pnpm build

This command:

- Performs full Solidity compilation with all optimizations
- Generates all contract artifacts (out/, abis/, dist/)
- Required for contract development, testing, and deployment
- Slower but comprehensive build process

### Documentation Builds

Build documentation sites:

    pnpm build:docs:coins    # Build coins documentation
    pnpm build:docs:nft      # Build NFT documentation

### Common Development Commands

Run tests:

    pnpm test

Run in development mode (watch tests):

    pnpm dev

Format and lint code:

    pnpm format
    pnpm lint

### When to Use Which Build

- **Use `pnpm build:js`** when:

  - Developing frontend applications with wagmi
  - Working with the SDK packages
  - You only need TypeScript definitions and ABIs
  - You want faster builds for iteration

- **Use `pnpm build`** when:
  - Developing or modifying Solidity contracts
  - Running comprehensive tests
  - Preparing for deployment
  - You need all contract artifacts

## About This Fork

This is a customized fork of the Zora Protocol adapted for the Niche ecosystem. The core protocol functionality remains the same, with the primary difference being the use of Niche coin as the backing currency for creator coins.

### Modified Files

Key files that reference the Niche coin:

- `packages/coins/src/libs/CoinConstants.sol` - Updated `CREATOR_COIN_CURRENCY`
- `packages/coins-sdk/src/utils/poolConfigUtils.ts` - Updated token address constants
- `docs/vocs.config.ts` - Updated branding to "Niche Docs"
- Documentation and test files updated throughout

### Original Protocol

This protocol is based on the Zora Protocol. For the original implementation, visit:

- [Original Zora Protocol Repository](https://github.com/ourzora/zora-protocol)
- [Zora Documentation](https://docs.zora.co)
