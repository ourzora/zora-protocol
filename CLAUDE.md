# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Documentation Philosophy

### Contract Documentation Guidelines

When documenting contracts, focus on **how to use** and **how it works** rather than technical reference material:

- **Prioritize user goals**: What does someone want to accomplish? (e.g., "Create a coin", "Understand rewards")
- **Use practical examples**: Show real code snippets and configuration values
- **Explain the "why"**: Help users understand the purpose and trade-offs of different options
- **Visual diagrams**: Use UML diagrams to show relationships and processes
- **Avoid redundancy**: Don't repeat information covered in other sections
- **Remove deprecated methods**: Only document current recommended approaches

### Writing Style for Contracts

- Use action-oriented headings (e.g., "Creating a Coin" vs "Coin Creation")
- Lead with benefits and outcomes, not implementation details
- Include decision-making guidance (e.g., "Use this configuration if...", "Choose based on...")
- Link strategically to related concepts and next steps

## Development Commands

### GitHub Actions Integration

**Claude Code Review Workflow:**
- Automatically runs on PRs with contract code changes
- Validates changeset presence for contract modifications
- Uses sticky comments to update reviews instead of creating multiple comments
- Configured with specific file path triggers and allowed tools for comprehensive validation
- Can be customized with different prompts based on PR author or file types

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

- `pnpm changeset` - Create a changeset describing your changes (interactive mode)
- `pnpm changeset add --empty` - Create an empty changeset file to manually edit
- Follow the interactive prompts to select packages and change types (patch, minor, major)
- Commit the generated changeset file along with your changes
- Changesets are used for automated version management and release notes

**Creating Empty Changesets for Manual Editing:**
- Use `pnpm changeset add --empty` to create an empty changeset file
- This generates a .changeset/*.md file that you can manually edit
- The file format should follow this structure:
  ```md
  ---
  "@zoralabs/package-name": patch | minor | major
  ---
  
  Description of changes
  
  - Bullet point details of what changed
  - Additional context or breaking changes
  ```

**Package Selection Guidelines:**
- When updating contract code, make a changeset for the corresponding contract package
- When updating a deployed address, make a changeset for `@zoralabs/protocol-deployments`

**Automated Changeset Validation:**
The Claude Code Review GitHub Action automatically validates that changesets are included when contract code is modified:
- Triggers on PRs that modify `.sol` files in `packages/*/src/`
- Also triggers on PR updates (`synchronize` event) not just creation
- Checks for presence of changeset files in `.changeset/` directory
- Reminds authors to add changesets when missing
- Uses `use_sticky_comment: true` to update existing comments rather than creating new ones
- Provides Claude with tools to inspect changesets: `pnpm changeset status`, `ls .changeset/`, etc.

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

### Coverage Analysis

To check test coverage for contracts:

**Generate Coverage Report:**
- `cd packages/{package-name}` (e.g., `cd packages/coins`)
- `pnpm run coverage` - Generate LCOV coverage report
- This runs: `forge coverage --report lcov --ir-minimum --no-match-coverage '(test/|src/utils/uniswap/|script/)'`

**Analyze Coverage Results:**
- Coverage report saved to `lcov.info` file
- Parse with: `awk '/^SF:src\// { file = $0; gsub("SF:", "", file); } /^LF:/ { total = $0; gsub("LF:", "", total); } /^LH:/ { covered = $0; gsub("LH:", "", covered); if (total > 0) printf "%-50s %3d/%3d lines (%5.1f%%)\n", file, covered, total, (covered/total)*100; }' lcov.info`

**Coverage Exclusions:**
- Check `.github/workflows/contracts.yml` for package-specific `ignore_coverage_files`
- Each package may exclude different files (e.g., `*test*`, `*lib*`, `*uniswap*`, etc.)
- Scripts and deployment files typically excluded via forge coverage flags

**CI Coverage:**
- Coverage checked automatically in GitHub Actions
- Minimum threshold varies by package (check contracts.yml)
- Coverage artifacts uploaded for failed runs
- LCOV reports available for download from CI runs

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

**Creating Branches:**
- `gt create {branch_name}` - Create a new branch stacked on current branch
- `gt create -a -m "message"` - Create branch, stage all changes, and commit with message
- `gt create --ai` - Auto-generate branch name and commit message from changes
- `gt commit create -m "message"` - Create commit on current branch (doesn't create new branch)

**Modifying Existing Branches:**
- `git add` - Stage changes manually, OR
- `gt modify -a` - Stage all changes and amend current commit
- `gt modify -c` - Create new commit instead of amending
- `gt modify -m "message"` - Amend with new commit message
- `gt modify -a -m "message"` - Stage all changes and amend with new message
- `gt submit` - Submit/update pull request

**Common Workflow:**
1. Make code changes
2. `gt modify -a -m "descriptive commit message"` - Stage and amend with message
3. `gt submit` - Update the PR with changes

**Graphite Create Options:**
- `-a, --all`: Stage all changes including untracked files
- `-i, --insert`: Insert branch between current and its child
- `-m, --message`: Specify commit message
- `-p, --patch`: Interactively select changes to stage
- `-u, --update`: Stage updates to tracked files only
- `--ai`: Auto-generate branch name and commit message

**Graphite Modify Options:**
- `-a, --all`: Stage all changes before committing
- `-c, --commit`: Create new commit instead of amending  
- `-e, --edit`: Open editor to edit commit message
- `-m, --message`: Specify commit message
- `-u, --update`: Stage updates to tracked files

**Key Differences:**
- `gt create` creates a NEW branch stacked on current branch
- `gt commit create` creates a commit on the CURRENT branch
- `gt modify` modifies the most recent commit on current branch

**Graphite Stacking Best Practices:**
- Break up changes/features into small branches for easier review and integration
- Use `gt create` to stack related changes on top of each other
- Each branch should represent a logical unit of work
- Submit stacked branches as separate PRs that can be reviewed independently
- Use descriptive branch names that reflect the specific change being made

### Legacy Integration

Legacy packages are maintained but not actively developed. They include:

- 1155-contracts: NFT creation and minting
- erc20z: ERC20 token creation with bonding curves
- sparks: Token-based reward system
- cointags: Social tagging for coins
