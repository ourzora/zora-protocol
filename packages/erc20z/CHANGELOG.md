# @zoralabs/erc20z

## 2.2.0

### Minor Changes

- 8358239c: This version bump updates the market reward from 0.0000111 ETH to 0.0000222 ETH and the mint referral reward from 0.0000222 ETH to 0.0000111 ETH 

## 2.1.1

### Patch Changes

- 63f9f6d4: Add a simple implementation() getter to the impl of the timed sale strategy for front-end and testing scripts.

## 2.0.3

### Patch Changes

- 66f33bbb: fix: update secondary swap helper contract address

## 2.0.2

### Patch Changes

- aba479af: Remove swap comments from SecondarySwap contract since it would be a breaking abi change
- 27f1d5e9: SecondarySwap supports comment in safeTransfer method of selling

## 2.0.1

### Patch Changes

- 5359c538: fix build

## 2.0.0

### Major Changes

- 879a019a: - Added `setSaleV2` and `SalesConfigV2` struct for creating V2 sales
  - Added `saleV2` and a composite `SaleData` struct for reading V2 sale data
  - Refactored `updateSale` to only apply to V2 sales
  - Replaced usage of the `SaleSet` event with `SaleSetV2` event which is emitted on sale creation, update, and market countdown
  - Updated `0x777777722D078c97c6ad07d9f36801e653E356Ae` across the following mainnets: Zora, Base, OP, Arb, Blast, Eth mainnet

## 1.0.1

### Patch Changes

- 6d32f374: SecondarySwap contract has a transfer hook enabling selling to happen in a single atomic transaction
- Updated dependencies [82f63033]
  - @zoralabs/zora-1155-contracts@2.12.4

## 1.0.0

### Major Changes

- 63db29bf: Major release

## 0.1.1

### Patch Changes

- Updated dependencies [9b487789]
  - @zoralabs/shared-contracts@0.0.1
  - @zoralabs/zora-1155-contracts@2.12.3

## 0.1.0

### Minor Changes

- 6b00336e: Deploy of SwapHelper
