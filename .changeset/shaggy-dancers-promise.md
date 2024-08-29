---
"@zoralabs/erc20z": major
---

- Added `setSaleV2` and `SalesConfigV2` struct for creating V2 sales
- Added `saleV2` and a composite `SaleData` struct for reading V2 sale data
- Refactored `updateSale` to only apply to V2 sales
- Replaced usage of the `SaleSet` event with `SaleSetV2` event which is emitted on sale creation, update, and market countdown
- Updated `0x777777722D078c97c6ad07d9f36801e653E356Ae` across the following mainnets: Zora, Base, OP, Arb, Blast, Eth mainnet
