# @zoralabs/protocol-deployments

## 0.1.9

### Patch Changes

- f4641f4b: Removed dependencies from `zora-1155-contracts`, `1155-deployments`, `mints-contracts`, and `mints-deployments`

## 0.1.8

### Patch Changes

- 8e514b7: Deployed lateset MintsEthUnwrapperAndCaller to chains

## 0.1.7

### Patch Changes

- b6fc3a4: Deployed latest ZoraMintsManagerImpl to zora and zora-sepolia
- 5e6a4b0: Added Protocol Rewards and ERC20 Minter abis and addresses to protocol-deployments

## 0.1.6

### Patch Changes

- 9a16b81: Remove graphql-request from hard dependencies in protocol sdk

## 0.1.5

### Patch Changes

- 042edbe: Chain ids in published protocol-deployments package are now numbers instead of strings
- 50a4e09: Includes MINTs contracts abis and addresses

## 0.1.4

### Patch Changes

- c2a0a2b: Moved dependencies to devDependencies since they are not needed by external users of the package, they are only used for codegen

## 0.1.3

### Patch Changes

- bb163d3: New preminter impl deployed to mainnet chains

## 0.1.2

### Patch Changes

- 52b16aa: Publishing package in format that supports commonjs imports by specifying exports
- Updated dependencies [52b16aa]
  - @zoralabs/zora-1155-contracts@2.7.3

## 0.1.1

### Patch Changes

- 8d6163c: Deployed to blast & blast sepolia.

## 0.1.0

### Minor Changes

- 653f625:
  - Configs & addresses bundled in the following format: `contracts{contractName}/addresses|chainConfigs/{chainId}/config`
  - Including bundled json output for each set of configs/addresses for a contract in the folder `bundled-configs`

## 0.0.14

### Patch Changes

- Added back protocol-deployments - bundling 1155-deployments into it

## 0.0.13

### Patch Changes

- f3332ee: Remove pgn chain configs and addresses
- d2085fd: Deployed to Arbitrum One & Arbitrum Sepolia
- a51a0cb: Renamed protocol-deployments to 1155-deployments
- Updated dependencies [8107ffe]
  - @zoralabs/zora-1155-contracts@2.7.1

## 0.0.12

### Patch Changes

- 3af77cf: Deploy 2.7.0 to mainnet, zora mainnet, zora sepolia, zora goerli, optimism, base
- 23dba1c: Deployed all contracts to sepolia

## 0.0.11

### Patch Changes

- bff853a: Include latest abi in protocol deployments

## 0.0.10

### Patch Changes

- 68c70a9: Tie protocol deployments to v2.5.4 of 1155
- Updated dependencies [f0c380d]
- Updated dependencies [98e78d7]
- Updated dependencies [050b689]
- Updated dependencies [3f8b18f]
  - @zoralabs/zora-1155-contracts@2.6.0

## 0.0.9

### Patch Changes

- 5156b9e: Deploy latest premint executor to zora sepolia and goerli
- Updated dependencies [7e00197]
  - @zoralabs/zora-1155-contracts@2.5.4

## 0.0.8

### Patch Changes

- 4b77307: Deployed 3.5.3 to zora sepolia and goerli

## 0.0.7

### Patch Changes

- 128b05c: Updated determinstic preminter deployment script to not fail if already deployed
- 1d58cd1: Deployed 2.5.2 to zora sepolia and zora goerli
- 128b05c: Deployed 2.5.1 to zora sepolia and zora goerli
- Updated dependencies [e4edaac]
  - @zoralabs/zora-1155-contracts@2.5.2

## 0.0.6

### Patch Changes

- f3b7df8: Deployed 2.4.0 with collaborators to zora-goerli, zora-sepolia, base, optimism, mainnet
- Updated dependencies [885ffa4]
- Updated dependencies [ffb5cb7]
- Updated dependencies [ffb5cb7]
- Updated dependencies [d84721a]
- Updated dependencies [cacb543]
  - @zoralabs/zora-1155-contracts@2.5.0

## 0.0.5

### Patch Changes

- 293e2c0: Moved deployment related code from 1155 to protocol-deployments package

## 0.0.4

### Patch Changes

- 6cfb6f9: Add Zora mainnet 1155 v2.3.1 deploy

## 0.0.3

### Patch Changes

- 85bdd23: Update Zora Network addresses to v2.3.0

## 0.0.2

### Patch Changes

- 4d79b49: Deployed to zora sepolia
- b62e471: created new package `protocol-deployments` that includes the deployed contract addresses.

  - 1155-contracts js no longer exports deployed addresses, just the abis
  - premint-sdk imports deployed addresses from `protocol-deployments

- 7d1a4c1: Deployed 2.3.0 to zora goerli

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
