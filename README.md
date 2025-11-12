> Note: Zora's ERC-721 Media contracts rely on the ModuleManager interface and should be deployed via the Zora Creator Factory.
# Zora Protocol

[![Contracts](https://github.com/ourzora/zora-protocol/actions/workflows/contracts.yml/badge.svg)](https://github.com/ourzora/zora-protocol/actions/workflows/contracts.yml)

This repository is a monorepo for the Zora Protocol.

In it you will find:

### Active Packages

- [Coins](./packages/coins)
- [Comments](./packages/comments)
- [Coins SDK](./packages/coins-sdk)
- [Protocol Deployments](./packages/protocol-deployments)
- [Smart Wallet](./packages/smart-wallet)

### Legacy Packages

- [Legacy Contracts](./legacy) - Contains legacy contract packages (1155-contracts, erc20z, sparks, cointags, protocol-sdk, etc.)

## Official docs

[View the official docs](https://docs.zora.co/docs/smart-contracts/creator-tools/intro)

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

## Bug Bounty

Report security vulnerabilities and learn about our Bug Bounty Program [here](https://docs.zora.co/bug-bounty/bug-bounty-program).
