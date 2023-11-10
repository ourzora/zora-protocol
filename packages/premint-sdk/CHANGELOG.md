# @zoralabs/premint-sdk

## 0.1.2-prerelease.0

### Patch Changes

- Updated dependencies [a50ae1c]
  - @zoralabs/protocol-deployments@0.0.5-prerelease.0

## 0.1.1

### Patch Changes

- b62e471: created new package `protocol-deployments` that includes the deployed contract addresses.

  - 1155-contracts js no longer exports deployed addresses, just the abis
  - premint-sdk imports deployed addresses from `protocol-deployments

- Updated dependencies [4d79b49]
- Updated dependencies [b62e471]
- Updated dependencies [7d1a4c1]
  - @zoralabs/protocol-deployments@0.0.2

## 0.1.0

### Minor Changes

- 4afa879: Added new premint api that abstracts out calls to the chain signature and submission logic around submitting a premint. This change also incorporates test helpers for premints and introduces docs and an api client for the zora api's premint module.

### Patch Changes

- Updated dependencies [4afa879]
  - @zoralabs/zora-1155-contracts@2.3.0

## 0.0.2-premint-api.2

### Patch Changes

- c29e080: Update retry and error reporting

## 0.0.2-premint-api.1

### Patch Changes

- 6eaf7bb: add retries

## 0.0.2-premint-api.0

### Patch Changes

- Updated dependencies [8395b8e]
- Updated dependencies [aae756b]
- Updated dependencies [cf184b3]
  - @zoralabs/zora-1155-contracts@2.1.1-premint-api.0
