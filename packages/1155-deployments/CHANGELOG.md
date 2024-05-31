# @zoralabs/1155-deployments

## 0.0.5

### Patch Changes

- 15a4c65d: Updates to latest deploys on ZORA and ZORA Sepolia.

## 0.0.4

### Patch Changes

- f08a0d01: Remove mints-deployments as dependency as it is now directly included in codegen.

  This fixes the package not being publish in npm and used only as an internal build package.

## 0.0.3

### Patch Changes

- c2a0a2b: Moved dev depenencies to devDependencies since they are not needed by external users of the package, they are only used for codegen

## 0.0.3

- 13a4785: Adds ERC20 Minter contract deployment addresses

## 0.0.2

### Patch Changes

- 9946d0a: Removed goerli, optimism-goerli, base-goerli, and zora-goerli from chain configs, addresses, and testing
- 28862f6: Deployed to blast sepolia and blast mainnet
- Updated dependencies [acf21c0]
  - @zoralabs/zora-1155-contracts@2.7.2
