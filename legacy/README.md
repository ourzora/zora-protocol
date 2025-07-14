# Legacy Contracts

This directory contains legacy contract packages that are no longer under active development but are maintained for historical purposes and ongoing support.

## Contents

- **1155-contracts** - Legacy Zora 1155 NFT contracts
- **1155-deployments** - Deployment configurations for 1155 contracts
- **erc20z** - ERC20Z token contracts
- **sparks** - Sparks protocol contracts
- **cointags** - Cointags contract system

## Development

Legacy contracts are built and tested using a separate CI workflow that runs only when manually triggered:

- Workflow: `.github/workflows/legacy_contracts.yml`
- Trigger: Manual execution via GitHub Actions UI (`workflow_dispatch`)

## Maintenance

These contracts are:
- ✅ Maintained for security updates
- ✅ Available for reference and historical purposes
- ❌ Not actively developed with new features
- ❌ Not automatically tested on every commit

## Migration

For current development, refer to the active contracts in the main `packages/` directory.