---
"@zoralabs/shared-contracts": patch
"@zoralabs/coins": minor
"@zoralabs/erc20z": patch
"@zoralabs/coins-sdk": patch
"@zoralabs/protocol-deployments": patch
---

- Publishing new coins hooks in `@zoralabs/protocol-deployments`
- In coins, pulling ISwapRouter from `@zoralabs/shared-contracts`, and updated the shared interface to match the full interface of the ISwapRouter. This new interface is published in `@zoralabs/protocol-deployments`.
- Removed publishing of the factory addresses directly in the wagmi config of the coins package, as that's inconsistent with the rest of the packages.
- Updated the `@zoralabs/coins-sdk` to use `@zoralabs/protocol-deployments` for abis and addresses, which significantly reduces the dependency tree of it and has it follow the patterns of the other sdk packages.
