---
"@zoralabs/protocol-sdk": patch
---

`MintAPIClient` is now a class, that takes a chain id and httpClient in the constructor, enabling the httpClient methods `fetch`, `post`, and `retries` to be overridden.

new methods on `MintAPIClient`:

`getMintableForToken` - takes a token id and token contract address and returns the mintable for it.  Easier to use for fetching specific tokens than `getMintable`.

`MintClient` now takes the optional `PublicClient` in the constructor instead of in each function, and stores it or creates a default one if none is provided in the constructor.  It also takes an optional `httpClient` param in the constructor, allowing the `fetch`, `post`, and `retries` methods to be overridden when using the api.  It now internally creates the MintAPIClient.

`MintClient.makePrepareMintTokenParams` has the following changes:
  * returns a `SimulateContractParams`, instead of an object containing it indexed by key
  * no longer takes a `PublicClient` as an argument (it should be specified in the constructor instead)

new function `MintClient.getMintCosts` takes a mintable and quantity to mint and returns the mintFee, paidMintPrice, and totalCost.