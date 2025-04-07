# Coins SDK

The `@zoralabs/coins-sdk` package allows developers to interact with the ZORA coins protocol.

This SDK is based off of viem v2 and exposes both functions to get the viem call to use with WAGMI, and also functions that complete the actions using the simulateContract and writeContract calls. Many reasonable defaults are set for fields, so read the action files and types to determine which parameters are needed for your actions.

Devs can input their addresses in `platformReferrer` and `traderReferrer` fields to earn trade and create referral fees for their platform.

This SDK has two main categories of functionality: Onchain Actions and Offchain Queries.

All the SDK functions are accessible from the main export (for example: `import {createCoin, getCoin} from "@zoralabs/coins-sdk"`).

All [documentation for coins](https://docs.zora.co/coins/sdk/getting-started) is available on [docs.zora.co](https://docs.zora.co/).

Contact us at [x.com/zoradevs](https://x.com/zoradevs) [warpcast/~/channel/zora-devs](https://warpcast.com/~/channel/zora-devs).


## Docs links

### Onchain Actions

- [createCoin](https://docs.zora.co/coins/sdk/create-coin)
- [tradeCoin](https://docs.zora.co/coins/sdk/trade-coin)
- [updateCoinURI](https://docs.zora.co/coins/sdk/update-coin)
- [updatePayoutRecipient](https://docs.zora.co/coins/sdk/update-coin#updating-payout-recipient)

### Queries

- Onchain queries
  - [getOnchainCoinDetails](https://docs.zora.co/coins/sdk/queries/onchain)
- [API Queries](https://docs.zora.co/coins/sdk/queries)
  - API Key
  - Cursor Pagination
  - Queries
    - [Coin queries](https://docs.zora.co/coins/sdk/queries/coin)
    - [Profile queries](https://docs.zora.co/coins/sdk/queries/profile)
    - [Explore queries](https://docs.zora.co/coins/sdk/queries/profile)
