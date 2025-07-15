# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Package Management

- `pnpm install` - Install dependencies
- `pnpm build` - Build all packages
- `pnpm test` - Run tests across all packages
- `pnpm dev` - Run development mode with watch tests
- `pnpm lint` - Run linting
- `pnpm format` - Format code with prettier

### Building & Release

- `pnpm build:docs:coins` - Build coins documentation site
- `pnpm build:docs:nft` - Build NFT documentation site
- `pnpm update-version` - Update package versions using changesets
- `pnpm release` - Build and publish packages

### Changesets

When making changes that affect public APIs or require version updates:

- `pnpm changeset` - Create a changeset describing your changes
- Follow the interactive prompts to select packages and change types (patch, minor, major)
- Commit the generated changeset file along with your changes
- Changesets are used for automated version management and release notes

**Package Selection Guidelines:**
- When updating contract code, make a changeset for the corresponding contract package
- When updating a deployed address, make a changeset for `@zoralabs/protocol-deployments`

### Protocol Deployments Architecture

The protocol deployments system follows a three-stage pipeline:

1. **Contract Packages** (e.g., `@zoralabs/coins`) - Generate ABIs via wagmi.config.ts
2. **`@zoralabs/protocol-deployments-gen`** - Combines ABIs with deployment addresses from all packages
3. **`@zoralabs/protocol-deployments`** - Published package with no hard dependencies

This architecture ensures the published deployments package remains dependency-free while consolidating all contract ABIs and addresses into a single consumable package.

### Testing

Tests are primarily Solidity-based using Foundry. For individual packages:

- Navigate to package directory (e.g., `cd packages/coins`)
- `forge test -vvv` - Run Solidity tests with verbose output
- `forge test --watch -vvv` - Run tests in watch mode
- `forge test -vvv --match-test {test_name}` - Run specific test
- `pnpm test` - Run JavaScript/TypeScript tests

### Bug Fix Workflow

For Solidity bugs:

1. Write a test to simulate the bug
2. Run the test with `forge test -vvv` to verify it fails
3. Fix the code to make the test pass
4. Verify the fix with the test suite

### New Feature Workflow

For new features:

1. Add minimal code to get feature compiling
2. Compile with `forge build`
3. Write tests to verify feature works
4. Commit code
5. Submit PR with `gt submit`

## Architecture Overview

### Repository Structure

This is a monorepo using pnpm workspaces with:

- **packages/**: Active development packages
- **legacy/**: Legacy contract packages (1155-contracts, erc20z, sparks, cointags, protocol-sdk)
- **docs/**: Documentation sites for coins and NFT protocols

### Key Active Packages

- **coins**: Core coins contracts and V4 Uniswap integration
- **coins-sdk**: SDK for interacting with coins contracts
- **comments**: Protocol for adding comments to NFTs and coins
- **creator-subgraph**: Graph protocol indexing for creator tools
- **protocol-deployments**: Contract deployment addresses and configurations
- **protocol-rewards**: Reward distribution contracts
- **smart-wallet**: Account abstraction wallet implementation

### Build System

Uses Turbo for monorepo task orchestration with dependency management:

- Contract compilation outputs to `out/` and `abis/` directories
- TypeScript packages output to `dist/`
- Foundry configuration in `foundry.toml` for Solidity projects
- Wagmi code generation for TypeScript contract interfaces

### Development Workflow

Uses Graphite for branch management:

- `gt create {new_branch}` - Create a new branch for features or bug fixes
- `gt commit create -m "message"` - Create commit with message
- `gt submit` - Submit pull request
- Make changes to existing branch, then:
  - `git add` - Stage changes
  - `gt modify` - Modify existing diff
  - `gt submit` - Update pull request after modifications

Break up changes/features into small branches for easier review and integration.

### Legacy Integration

Legacy packages are maintained but not actively developed. They include:

- 1155-contracts: NFT creation and minting
- erc20z: ERC20 token creation with bonding curves
- sparks: Token-based reward system
- cointags: Social tagging for coins
