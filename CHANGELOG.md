# @zoralabs/zora-1155-contracts

## 2.0.3

### Patch Changes

- d3ddfbb: fix version packages tests

## 2.0.2

### Patch Changes

- 9207e8f: Deployed determinstic proxies and latest versions to mainnet, goerli, base, base goerli, optimism, optimism goerli

## 2.0.1

### Patch Changes

- 35db763: Adding in built artifacts to package

## 2.0.0

### Major Changes

- 82f6506: Premint with Delegated Minting
  Determinstic Proxy Addresses
  Premint deployed to zora and zora goerli

## 1.6.1

### Patch Changes

- b83e1b6: Add first minter payouts as chain sponsor

## 1.6.0

### Minor Changes

- 399b8e6: Adds first minter rewards to zora 1155 contracts.
- 399b8e6: Added deterministic contract creation from the Zora1155 factory, Preminter, and Upgrade Gate
- 399b8e6: Added the PremintExecutor contract, and updated erc1155 to support delegated minting

* Add first minter rewards
* [Separate upgrade gate into new contract](https://github.com/ourzora/zora-1155-contracts/pull/204)

## 1.5.0

### Minor Changes

- 1bf2d52: Add TokenId to redeemInstructionsHashIsAllowed for Redeem Contracts
- a170f1f: - Patches the 1155 `callSale` function to ensure that the token id passed matches the token id encoded in the generic calldata to forward
  - Updates the redeem minter to v1.1.0 to support b2r per an 1155 token id

### Patch Changes

- b1dbb47: Fix types reference for package export
- 4cb56d4: - Ensures sales configs can only be updated for the token ids specified
  - Deprecates support with 'ZoraCreatorRedeemMinterStrategy' v1.0.1

## 1.4.0

### Minor Changes

- 5b3fafd: Change permission checks for contracts – fix allowing roles that are not admin assigned to tokenid 0 to apply those roles to any token in the contract.
- 9f6510d: Add support for rewards

  - Add new minting functions supporting rewards
  - Add new "rewards" library

## 1.3.3

### Patch Changes

- 498998f: Added pgn sepolia
  Added pgn mainnet
- cc3b55a: New base mainnet deploy
