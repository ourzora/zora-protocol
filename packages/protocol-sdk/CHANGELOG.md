# @zoralabs/protocol-sdk

## 0.5.12

### Patch Changes

- e2452f7d: Removed `zora-1155-contracts`, `1155-deployments`, `mints-contracts`, and `mints-deployments` from devDependencies hierarchy.

## 0.5.11

### Patch Changes

- 8e514b7: Cleanup protocol-sdk to have better docs around all methods, and remove methods that do not need to be exported and are not used.
- 598a95b: Bumps protocol-sdk to use viem@2.x- see the [viem 2.X.X migration guide](https://viem.sh/docs/migration-guide#2xx-breaking-changes) for breaking changes when migratring from viem 1.X.X to 2.X.X
- Updated dependencies [8e514b7]
  - @zoralabs/protocol-deployments@0.1.8

## 0.5.10

### Patch Changes

- Updated dependencies [9a16b81]
  - @zoralabs/protocol-deployments@0.1.6

## 0.5.9

### Patch Changes

- 825e5f7: Adds optional `createReferral` to `createNew1155Token` params

## 0.5.8

### Patch Changes

- 50a4e09: Added sdk method to get total MINT balance
- Updated dependencies [042edbe]
- Updated dependencies [50a4e09]
  - @zoralabs/protocol-deployments@0.1.5

## 0.5.7

### Patch Changes

- 2eda168: Update default premint version to v2
- 4066420: Adding protocol SDK to base and sepolia networks
- Updated dependencies [bb163d3]
  - @zoralabs/protocol-deployments@0.1.3

## 0.5.6

### Patch Changes

- 52b16aa: Publishing package in format that supports commonjs imports by specifying exports
- Updated dependencies [52b16aa]
  - @zoralabs/protocol-deployments@0.1.2

## 0.5.5

### Patch Changes

- 8a87809: Undo changes to package export because it didn't properly bundle all files in `dist`

## 0.5.4

### Patch Changes

- 9710e5e: Defining exports in protocol-sdk

## 0.5.3

### Patch Changes

- a07499d: Allows an `Account` object to be passed for `signTypedData` compatiblity with Local Accounts

## 0.5.2

### Patch Changes

- 5c536dc: Update optimism eth constant
- Updated dependencies [f3332ee]
- Updated dependencies [d2085fd]
- Updated dependencies [a51a0cb]
  - @zoralabs/1155-deployments@0.0.13

## 0.5.1

### Patch Changes

- 73070c0:
  - Fix types export - make sure that types are exported to the correct directory. Broken by commit 627f8c37716f0b5c201f75ab1d025ae878be0ae29e7a269d21185fa04e4bcf93
  - Exclude tests from built bundle
  - Fixes #396

## 0.5.0

### Minor Changes

- a52d245: Fix premint v2 support in premint client and add support for sepolia to SDK:

  - Fix chain constants config for Zora Goerli.
  - Support Zora-Sepolia for premint client.
  - Fix passing of `config_version` to and from the backend API.
  - Change parameter on `makeMintParameters` from `account` to `minterAccount`.
  - Fix price minter address for premint client by chain, since it is not the same on all chains (yet).

### Patch Changes

- Updated dependencies [3af77cf]
- Updated dependencies [23dba1c]
  - @zoralabs/protocol-deployments@0.0.12

## 0.4.3

### Patch Changes

- 92b1b0e: Export premint conversions

## 0.4.2

### Patch Changes

- 9b03ed2: Support premint v2 in sdk
- Updated dependencies [bff853a]
  - @zoralabs/protocol-deployments@0.0.11

## 0.4.1

### Patch Changes

- 7e00197: \* For premintV1 and V2 - mintReferrer has been changed to an array `mintRewardsRecipients` - which the first element in array is `mintReferral`, and second element is `platformReferral`. `platformReferral is not used by the premint contract yet`.
- 0ceb709: Add mint costs getter for premint to protocol sdk
- Updated dependencies [5156b9e]
  - @zoralabs/protocol-deployments@0.0.9

## 0.4.0

### Minor Changes

- 28884c9: \* `PremintClient` now takes a premint config v1 or v2, and a premint config version, for every call to create/update/delete a premint. PremintClient methods have been simplified and are easier to use - for example `createPremint` no longer allows to specify `deleted` = true. For `makeMintParameters` - it now just takes the uid and contract address (instead of full premint config)
  - `PremintAPIClient` now converts entities to contract entities before returning them, and correspondingly expects them as contract entities when passed in. It internally converts them to backend entities before sending them to the backend.

### Patch Changes

- Updated dependencies [4b77307]
  - @zoralabs/protocol-deployments@0.0.8

## 0.3.5

### Patch Changes

- 7eb5e3f: ### Changes to `preminter`

  lower level `preminter.ts` now supports premint v2 by defining v2 typed data defintions.

  - `isValidSignature` now takes either v1 or v2 of a premint config, along with the premint config version. and both recovers the signer address and validates if the signer can create a premint on the given contract.
  - new function `premintTypedDataDefinition` which takes a premint config version and returns the signable typed data definition for that version
  - new function `recoverCreatorFromCreatorAttribution` which recovers the creator address from a `CreatorAttribution` event
  - new function `supportsPremintVersion` which checks if a given token contract supports a given premint config version
  - new function `tryRecoverPremintSigner` which takes a premint config version and a premint signature, and tries to recover the signer address from the signature. If the signature is invalid, it returns undefined.

  ### Changes to PremintClient

  `PremintClient` creation, updating, and deletion now take both premint config v1 and v2, but currently rejects them until the backend api supports creating v2 premints.

  - `isValidSignature` now just takes the data directly as a param, instead of `{data}`

- 27a2e23: Fix reading the FIXED_PRICE_MINTER from the subgraph

## 0.3.4

### Patch Changes

- ea27f01: Fix reading the FIXED_PRICE_MINTER from the subgraph

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
