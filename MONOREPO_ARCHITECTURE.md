# Zora Protocol Monorepo Architecture Guide

This comprehensive technical guide documents the monorepo setup, build system architecture, and patterns that future agents need to understand to work effectively with the Zora Protocol codebase.

**For day-to-day development commands and workflows, see [CLAUDE.md](CLAUDE.md).**

## Table of Contents

1. [Build System Architecture](#build-system-architecture)
2. [Package Categorization & Patterns](#package-categorization--patterns)
3. [Build Optimization Learnings](#build-optimization-learnings)
4. [Monorepo-Specific Gotchas](#monorepo-specific-gotchas)
5. [Developer Workflow Patterns](#developer-workflow-patterns)
6. [Dependency Chain Analysis](#dependency-chain-analysis)
7. [Performance Optimization Strategies](#performance-optimization-strategies)
8. [Common Failure Patterns and Solutions](#common-failure-patterns-and-solutions)
9. [How to Publish a Contract in protocol-deployments](#how-to-publish-a-contract-in-protocol-deployments)
10. [Best Practices for Future Development](#best-practices-for-future-development)

## Build System Architecture

### Core Build Tasks Overview

The monorepo uses Turbo for orchestration with distinct build task patterns:

- **`build`**: Full contract compilation + TypeScript builds + ABI generation
- **`build:js`**: Minimal contract compilation + wagmi generation + TypeScript output only
- **`build:contracts:minimal`**: Forge compilation without tests, scripts, or metadata
- **`build:site`**: Documentation site builds (depends on `build:js`)

### Build vs build:js Distinction

**Key Insight**: The `build:js` task was introduced specifically for wagmi consumption and documentation builds to avoid unnecessary contract compilation overhead.

#### When build:js is used:

- Documentation builds (`build:site` depends on `^build:js`)
- CI/CD JavaScript testing pipeline
- Package consumption by external tools (wagmi, SDK generation)
- Development workflows that only need TypeScript/ABI outputs

#### When full build is used:

- Release preparation (`pnpm release` uses `turbo run build`)
- Contract testing and deployment
- Gas reporting and coverage analysis
- Storage layout verification

**Critical Dependencies**:

- The internal generation package's `build:js` depends on `^build:js` from all contract packages
- The published deployment package's `build:js` depends specifically on the internal generation package
- Documentation builds use `build:js` to avoid unnecessary Solidity compilation

## Package Categorization & Patterns

### Active Packages (`packages/`)

#### Contract Packages (Foundry + TypeScript)

Contract packages are identified by the presence of `foundry.toml` and `wagmi.config.ts` files. These packages follow a hybrid compilation pattern supporting both Solidity contract development and TypeScript consumption. Examples include packages focused on core protocol contracts, commenting systems, shared contract utilities, and wallet implementations.

**Identification Pattern**: Look for packages containing both:

- `foundry.toml` - Foundry configuration for Solidity compilation
- `wagmi.config.ts` - Wagmi configuration for TypeScript ABI generation

**Build Pattern**:

```jsonc
{
  "build": "forge build", // Full compilation
  "build:contracts:minimal": "forge build --skip test --skip script --no-metadata",
  "wagmi:generate": "pnpm run build:contracts:minimal && wagmi generate && pnpm exec rename-generated-abi-casing",
  "build:js": "pnpm run wagmi:generate && pnpm run copy-abis && pnpm run prettier:write && tsup",
}
```

#### TypeScript-Only Packages

These packages focus on consumption APIs, tooling, and build utilities. They contain only TypeScript/JavaScript code without Solidity contracts. Examples include SDK packages for contract interaction, deployment configuration packages, internal code generation utilities, and shared build tooling.

**Identification Pattern**: Look for packages with:

- `tsconfig.json` or `tsup.config.ts` but no `foundry.toml`
- Primary focus on JavaScript/TypeScript build outputs
- Often serve as consumption layers or development tooling

**Build Pattern**:

```json
{
  "build": "pnpm tsup",
  "build:js": "pnpm run build"
}
```

### Legacy Packages (`legacy/`)

**Key Insight**: Legacy packages maintain backward compatibility but follow similar patterns to active packages after the build optimization.

#### Legacy Package Characteristics

Legacy packages in the `legacy/` directory represent previous iterations of protocol components. They maintain the same architectural patterns as active packages (contract + TypeScript hybrids or TypeScript-only) but are no longer the primary development focus. These packages often represent superseded implementations or earlier protocol versions that remain for compatibility.

**Identification Pattern**:

- Located in `legacy/` directory
- May follow older build patterns but have been updated for performance
- Often have newer equivalents in the main `packages/` directory

**Legacy Build Evolution**: Recent commits show legacy packages were updated to use `build:contracts:minimal` instead of full `FOUNDRY_PROFILE=dev forge build`, significantly improving build performance.

### Documentation Packages

Documentation packages are typically found in the root directory and focus on static site generation. They depend on TypeScript packages for type information and use frameworks like Vocs for MDX processing.

**Identification Pattern**:

- Located in root directory or dedicated docs folders
- Contain `vocs.config.ts` or similar static site configuration
- Depend on `^build:js` from SDK packages for type generation

**Build Dependencies**: Documentation builds depend on `build:js` from SDK packages, ensuring they have access to generated types without triggering expensive contract compilation.

## Build Optimization Learnings

### The wagmi Generation Optimization

**Problem**: Documentation builds and CI were running full contract compilation when they only needed TypeScript types and ABIs.

**Solution**: Introduction of `build:contracts:minimal` pattern:

```bash
# Before (slow)
FOUNDRY_PROFILE=dev forge build && wagmi generate

# After (fast)
pnpm run build:contracts:minimal && wagmi generate
# Where build:contracts:minimal = "forge build --skip test --skip script --no-metadata"
```

**Performance Impact**:

- Skips test compilation (major time saver)
- Skips script compilation
- Removes metadata generation
- Reduces build artifacts by ~70%
- Maintains full wagmi compatibility

### Contract Build Variants

1. **Full Build** (`forge build`): All contracts, tests, scripts, metadata
2. **Minimal Build** (`forge build --skip test --skip script --no-metadata`): Production contracts only
3. **Size Analysis** (`forge build --sizes`): Contract size reporting
4. **Dev Profile** (`FOUNDRY_PROFILE=dev forge build`): Legacy pattern, now replaced

### Cache Behavior and Optimization

**Turbo Caching Strategy**:

- All build tasks cache outputs to `dist/**`, `out/**`, `abis/**`
- `dev` task explicitly disables cache (`"cache": false`) and runs persistently
- Cache keys include package dependencies and source file changes
- Documentation builds benefit from cached `build:js` outputs

## Monorepo-Specific Gotchas

### 1. Protocol Deployments Dependency Chain

**Critical Pattern**: The protocol-deployments system uses a sophisticated three-stage dependency isolation pipeline:

```
Contract Packages → protocol-deployments-gen → protocol-deployments
```

**Architectural Goal: Dependency-Free Published Package**

The entire architecture is designed around a core constraint: `protocol-deployments` must be dependency-free for external consumption. This clean published package allows external developers to import Zora Protocol ABIs and addresses without pulling in the entire monorepo's transitive dependencies.

**Separation of Concerns**:

- **`protocol-deployments-gen`** (Internal Build Tool):

  - Has dependencies on internal/non-published monorepo packages
  - Aggregates ABIs and deployment addresses from ALL contract packages
  - Pulls data from both `packages/` and `legacy/` directories
  - Bundles everything into generated code files
  - Never published to npm - purely internal tooling

- **`protocol-deployments`** (Clean Published Package):
  - Zero dependencies in package.json
  - Contains only generated code from the -gen package
  - Published to npm for external consumption
  - Provides wagmi-compatible types and ABIs
  - Clean API surface for external developers

**Generation Process**:

1. Contract packages compile and generate ABIs via wagmi
2. `protocol-deployments-gen` imports ABIs from all contract packages using workspace references
3. The -gen package bundles ABIs with deployment addresses into consolidated files
4. Generated code is written directly into `protocol-deployments` package
5. `protocol-deployments` builds and publishes the generated code with no dependencies

**Why This Pattern Matters**:

- **External Consumption**: Wagmi users get a clean package without monorepo complexity
- **Dependency Isolation**: No risk of version conflicts from internal tooling
- **Maintainability**: Internal refactoring doesn't break external consumers
- **Performance**: Smaller dependency graph for external applications
- **Monorepo Flexibility**: Internal packages can change without affecting public API

**Common Failure**: If you update a contract package but don't trigger `protocol-deployments-gen`'s `build:js`, the published `protocol-deployments` package won't include the new ABIs. The generation step is critical for propagating changes.

### 2. Wagmi Configuration Dependencies

**Complex Wagmi Setup**: The internal generation package's `wagmi.config.ts` imports from ALL contract packages in both `packages/` and `legacy/` directories.

```typescript
// Pattern: imports from all contract packages
import * as abis from "@zoralabs/package-name";
import { specificABI } from "@zoralabs/another-package";
// ... imports from all packages with foundry.toml
```

**Gotcha**: This configuration file must be manually updated when contract packages add new exports or when new contract packages are added to the monorepo.

### 3. Build Order Requirements

**Turbo Handles Most Ordering**, but be aware:

- Internal generation packages (\*-gen) MUST build before their corresponding published packages
- Documentation packages need SDK packages built first
- Wagmi generation requires contract compilation to complete
- Shared utilities must build before packages that depend on them

### 4. Foundry Profile Pitfalls

**Legacy Issue**: Old packages used `FOUNDRY_PROFILE=dev` but this is being phased out in favor of explicit forge flags.

**Best Practice**: Use explicit forge flags rather than profiles:

```bash
# Good
forge build --skip test --skip script

# Avoid (legacy pattern)
FOUNDRY_PROFILE=dev forge build
```

## Developer Workflow Patterns

### When to Use Which Commands

**Development (Fast Iteration)**:

```bash
pnpm build:js    # TypeScript + minimal contracts
pnpm dev         # Watch mode for testing
```

**Documentation Work**:

```bash
pnpm build:docs:coins  # Builds site with optimized dependencies
pnpm docs:preview      # Local preview
```

**Contract Development**:

```bash
cd packages/coins
forge test -vv         # Test specific package
pnpm build             # Full build with ABIs
```

**Release Preparation**:

```bash
pnpm build            # Full compilation of everything
pnpm test             # Complete test suite
pnpm changeset        # Version management
```

**For complete command reference, see [CLAUDE.md](CLAUDE.md#development-commands).**

### Testing Strategies

**Contract Testing**: Foundry-based per package

```bash
cd packages/coins
forge test -vvv
forge test --watch -vvv  # Watch mode
```

**Integration Testing**: TypeScript-based

```bash
pnpm test:integration    # In SDK packages
```

**Coverage Analysis**:

```bash
pnpm run coverage       # Generates LCOV reports
```

**For detailed testing workflows, see [CLAUDE.md](CLAUDE.md#testing).**

### Documentation Build System

**Two Documentation Sites**:

- `docs/`: Coins protocol (primary)
- `nft-docs/`: Legacy NFT protocol

**Build Process**:

1. Documentation depends on `^build:js` from SDK packages
2. Vocs builds static sites with MDX processing
3. TypeScript types are generated from wagmi ABIs
4. Sites deploy to Vercel with optimized caching

**Performance Optimization**: Documentation builds avoid contract compilation by depending only on `build:js`, reducing build time from ~5min to ~30sec.

## Dependency Chain Analysis

### Package Interdependencies

**High-Level Flow**:

```
Contract Packages (packages/*/ with foundry.toml)
    ↓ (ABIs + addresses)
Internal Generation Package (*-gen)
    ↓ (consolidated wagmi types)
Published Deployment Package
    ↓ (published package)
SDK Packages, Documentation Sites
```

**Workspace Dependencies** (uses `workspace:^`):

- Most packages depend on shared TypeScript configuration
- Contract packages depend on shared build tooling and scripts
- SDK packages depend on the main protocol deployments package
- Documentation sites depend on SDK packages for type information

### Critical Path Dependencies

1. **Shared Build Utilities**: Common tooling used across all contract packages
2. **Internal Generation Package**: Aggregation point for all contract ABIs (typically named \*-gen)
3. **Published Deployment Package**: Public API for external contract interactions

**Failure Points**:

- If shared build utilities fail, all contract package builds fail
- If the internal generation package fails, no external packages get updated ABIs
- If shared TypeScript configuration fails, all TypeScript builds fail

## Performance Optimization Strategies

### Build Time Optimizations

1. **Minimal Contract Builds**: Use `--skip test --skip script --no-metadata` for wagmi generation
2. **Targeted Documentation Builds**: Use `build:js` dependencies to avoid unnecessary compilation
3. **Incremental TypeScript**: tsup with `onSuccess` hooks for declaration generation
4. **Turbo Caching**: Proper output declarations for effective caching

### CI/CD Optimizations

**JavaScript Pipeline**: Uses `pnpm turbo run build:js` instead of full build
**Contract Pipeline**: Full build only for contract-specific changes
**Documentation Pipeline**: Optimized builds with wagmi-only dependencies

### Memory and Resource Management

**Large Packages**: 1155-contracts and coins are memory-intensive due to complex Solidity compilation
**Parallel Builds**: Turbo runs compatible packages in parallel
**Resource Limits**: Some packages may need `--max_old_space_size` for Node.js

## Common Failure Patterns and Solutions

### 1. "Cannot find module" in wagmi generation

**Cause**: Package dependencies not built in correct order
**Solution**: Ensure `^build:js` dependencies are correct in turbo.json

### 2. Outdated ABIs in published packages

**Cause**: Internal generation package not rebuilt after contract changes
**Solution**: Run `pnpm turbo run build:js` from root

### 3. Documentation build failures

**Cause**: Missing TypeScript types from SDK packages
**Solution**: Verify docs depend on `^build:js` from required SDKs

### 4. Forge compilation OOM

**Cause**: Large contract dependencies (especially Uniswap V4)
**Solution**: Use `build:contracts:minimal` or increase Node memory

### 5. Cache invalidation issues

**Cause**: Turbo cache not recognizing source changes
**Solution**: Clear cache with `turbo run build --force`

## How to Publish a Contract in protocol-deployments

This section provides step-by-step instructions for adding new contracts to the published `@zoralabs/protocol-deployments` package, making them available for wagmi consumption by external developers.

### Overview of the Publication Flow

The protocol-deployments system uses a three-stage pipeline to convert individual contract packages into a clean, dependency-free published package:

```
1. Individual Package (e.g., coins/)
   └── wagmi.config.ts defines which contracts to export
   └── addresses/*.json files contain deployment addresses

2. protocol-deployments-gen/ (Internal Generation Tool)
   └── wagmi.config.ts imports ABIs from all packages
   └── Combines ABIs with addresses into consolidated wagmi types
   └── Outputs generated/wagmi.ts

3. protocol-deployments/ (Published Package)
   └── copy-generated script copies the generated file
   └── Zero dependencies for clean external consumption
```

### Step 1: Add Contract to Package wagmi.config.ts

In your contract package (e.g., `packages/coins/wagmi.config.ts`), add the contract name to the `include` array:

```typescript
// packages/coins/wagmi.config.ts
export default defineConfig({
  out: "package/wagmiGenerated.ts",
  plugins: [
    foundry({
      forge: {
        build: false,
      },
      include: [
        "BaseCoin", // Existing contract
        "CreatorCoin", // Existing contract
        "YourNewContract", // ← Add your new contract here
        // ... other contracts
      ].map((contractName) => `${contractName}.json`),
    }),
  ],
});
```

**Key Points**:

- Only include contracts that should be publicly available
- Contract names must match the Solidity contract names exactly
- The `.json` extension is added automatically by the `.map()` function

### Step 2: Update protocol-deployments-gen/wagmi.config.ts

This is the most complex step. You need to update `/packages/protocol-deployments-gen/wagmi.config.ts` to import your new ABI and handle it appropriately.

#### 2.1: Import the ABI

Add your contract ABI to the imports at the top of the file:

```typescript
// At the top of protocol-deployments-gen/wagmi.config.ts
import {
  zoraFactoryImplABI,
  baseCoinABI,
  creatorCoinABI,
  yourNewContractABI, // ← Add this import
  // ... other imports
} from "@zoralabs/coins"; // or your package name
```

#### 2.2: Add to Appropriate Getter Function

Find or create the appropriate getter function for your package. For example, coins contracts go in `getCoinsContracts()`:

**For Address-Based Contracts** (deployed contracts with known addresses):

```typescript
const getCoinsContracts = (): ContractConfig[] => {
  const addresses: Addresses = {};

  // ... existing address loading logic ...

  // Add your contract with addresses
  addAddress({
    abi: yourNewContractABI,
    addresses,
    configKey: "YOUR_NEW_CONTRACT", // Must match key in addresses/*.json
    contractName: "YourNewContract", // Name in final wagmi types
    storedConfigs,
  });

  return [
    ...toConfig(addresses),
    // ... existing ABI-only contracts ...
  ];
};
```

**For ABI-Only Contracts** (interfaces, no deployment addresses needed):

```typescript
const getCoinsContracts = (): ContractConfig[] => {
  // ... existing address-based contracts ...

  return [
    ...toConfig(addresses),
    {
      abi: yourNewContractABI,
      name: "YourNewContract",
    },
    // ... other ABI-only contracts ...
  ];
};
```

#### 2.3: Handle Error Extraction (If Needed)

Some contracts combine errors from multiple ABIs. Follow this pattern if your contract needs error handling:

```typescript
addAddress({
  abi: [
    ...yourNewContractABI,
    ...extractErrors(someOtherContractABI), // Include related errors
  ],
  addresses,
  configKey: "YOUR_NEW_CONTRACT",
  contractName: "YourNewContract",
  storedConfigs,
});
```

### Step 3: Ensure Address Files Are Available (If Applicable)

If your contract has deployment addresses, create address files in your package's `addresses/` directory:

**File Format**: `packages/your-package/addresses/{chainId}.json`

```json
{
  "YOUR_NEW_CONTRACT": "0x1234567890123456789012345678901234567890",
  "EXISTING_CONTRACT": "0x...",
  "OTHER_ADDRESSES": "0x..."
}
```

**Examples**:

- `packages/coins/addresses/8453.json` (Base mainnet)
- `packages/coins/addresses/1.json` (Ethereum mainnet)
- `packages/coins/addresses/dev/31337.json` (Local development)

**Key Requirements**:

- Use uppercase with underscores for JSON keys
- Keys must match the `configKey` used in `addAddress()` calls
- Addresses must be valid hex strings with `0x` prefix

### Step 4: Run the Generation Process

Execute these commands in the correct order to propagate your changes:

```bash
# 1. Build your package to generate fresh ABIs
pnpm --filter @zoralabs/your-package build:js

# 2. Build the generation package to create consolidated wagmi types
pnpm --filter @zoralabs/protocol-deployments-gen build:js

# 3. Build the published package to copy generated files
pnpm --filter @zoralabs/protocol-deployments build:js
```

**Alternative**: Build all related packages at once:

```bash
pnpm turbo run build:js --filter="@zoralabs/protocol-deployments*" --filter="@zoralabs/your-package"
```

### Verification Steps

After completing the generation process, verify your contract is properly published:

1. **Check Generated File**:

   ```bash
   # Look for your contract in the generated wagmi types
   cat packages/protocol-deployments-gen/generated/wagmi.ts | grep -A 10 "YourNewContract"
   ```

2. **Verify in Published Package**:

   ```bash
   # Ensure the generated file was copied
   cat packages/protocol-deployments/src/generated/wagmi.ts | grep "YourNewContract"
   ```

3. **Test Import**:
   ```typescript
   // Test that external consumers can import your contract
   import { yourNewContractABI } from "@zoralabs/protocol-deployments";
   ```

### Troubleshooting Common Issues

**"Cannot find module" Errors**:

- Ensure the contract package has been built with `build:js`
- Check that the import path matches the package name exactly
- Verify the ABI is exported from the package's main index file

**Missing Addresses**:

- Confirm address files exist in the expected location
- Check that JSON keys match the `configKey` exactly (case-sensitive)
- Ensure addresses are valid hex strings with `0x` prefix

**Build Order Issues**:

- Always build the source package before the generation package
- Use turbo to handle dependency ordering automatically
- Check that `^build:js` dependencies are correct in turbo.json

**Outdated ABIs**:

- Clear turbo cache with `turbo run build:js --force` if needed
- Ensure contract compilation produced fresh ABIs
- Verify the contract name matches between Solidity and wagmi.config.ts

This systematic approach ensures your contracts become available to external wagmi consumers while maintaining the clean, dependency-free architecture of the protocol-deployments package.

## Best Practices for Future Development

### Adding New Contract Packages

1. Follow the established script pattern with `build`, `build:js`, `build:contracts:minimal`
2. Add package exports to the internal generation package's `wagmi.config.ts`
3. Update the internal generation package's `package.json` dependencies
4. Ensure proper tsup configuration for TypeScript builds
5. Follow the foundry.toml + wagmi.config.ts pattern for contract packages

### Modifying Build Dependencies

1. Update turbo.json with correct dependency chains
2. Test with `pnpm turbo run build:js --dry-run` to verify order
3. Check documentation builds still work
4. Verify CI pipeline changes

### Performance Considerations

1. Prefer `build:js` for non-release workflows
2. Use explicit forge flags instead of Foundry profiles
3. Keep contract dependencies minimal
4. Consider build time impact when adding new dependencies

This architecture has evolved to support efficient development while maintaining backward compatibility and enabling external consumption through wagmi. The key insight is the separation of concerns between full contract development builds and consumption-focused builds for TypeScript tooling.
