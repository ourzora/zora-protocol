---
"@zoralabs/protocol-sdk": patch
---

- Adds new fields to `SecondaryInfo` type to expose more information about the secondary market configuration:

  - `name`: The ERC20Z token name
  - `symbol`: The ERC20Z token symbol
  - `saleStart`: Earliest time tokens can be minted
  - `marketCountdown`: Time after minimum mints reached until secondary market launches
  - `minimumMintsForCountdown`: Minimum mints required to start countdown
  - `mintCount`: Total number of tokens minted so far

- Deprecates `minimumMarketEth` parameter in favor of `minimumMintsForCountdown` when creating tokens:
  - `minimumMintsForCountdown` directly specifies minimum number of mints (defaults to `1111`)
  - `minimumMarketEth` is still supported but calculated internally as `minimumMintsForCountdown * 0.0000111 ETH`
