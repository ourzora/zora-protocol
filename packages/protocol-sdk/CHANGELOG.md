# @zoralabs/protocol-sdk

## 0.3.3

### Patch Changes

- 97f58b3: `MintAPIClient` is now a class, that takes a chain id and httpClient in the constructor, enabling the httpClient methods `fetch`, `post`, and `retries` to be overridden.

  new methods on `MintAPIClient`:

  `getMintableForToken` - takes a token id and token contract address and returns the mintable for it. Easier to use for fetching specific tokens than `getMintable`.

  `MintClient` now takes the optional `PublicClient` in the constructor instead of in each function, and stores it or creates a default one if none is provided in the constructor. It also takes an optional `httpClient` param in the constructor, allowing the `fetch`, `post`, and `retries` methods to be overridden when using the api. It now internally creates the MintAPIClient.

  `MintClient.makePrepareMintTokenParams` has the following changes:

  - returns a `SimulateContractParams`, instead of an object containing it indexed by key
  - no longer takes a `PublicClient` as an argument (it should be specified in the constructor instead)

  new function `MintClient.getMintCosts` takes a mintable and quantity to mint and returns the mintFee, paidMintPrice, and totalCost.

- d02484e: premintClient can have http methods overridable via DI, and now takes publicClient and http overrides in `createPremintClient` function. it no longer takes `publicClient` as an argument in functions, and rather uses them from the constructor. `executePremint` has been renamed ot `makeMintParameters`

## 0.3.2

### Patch Changes

- de0b0b7: `preminter` exposes new function isValidSignatureV1 that recovers a signer from a signed premint and determines if that signer is authorized to sign
- Updated dependencies [f3b7df8]
  - @zoralabs/protocol-deployments@0.0.6

## 0.3.1

### Patch Changes

- 92da3ed: Exporting mint client
- Updated dependencies [293e2c0]
  - @zoralabs/protocol-deployments@0.0.5

## 0.3.0

### Minor Changes

- 40e0b32:
  - rename premint-sdk to protocol-sdk
  - added minting sdk, usable with `createMintClient`
  - added 1155 creation sdk, usable with `create1155CreatorClient`
  - premint sdk is now useable with `createPremintClient`

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
