---
"@zoralabs/coins-sdk": minor
---

Create coin flow now uses server-generated calldata via the SDK API. This enables smart account compatibility and future extensibility while simplifying client-side logic.

- **Server-generated calldata**: `createCoinCall` now requests calldata from the SDK API and returns an array of transaction parameters `{ to, data, value }[]` instead of a Viem `SimulateContractParameters` object.
- **Direct transaction sending**: `createCoin` constructs and sends the transaction using `walletClient.sendTransaction` with manual gas estimation and an option to skip validation.
- **Sanity checks**: Ensures the call targets the expected factory for the specified `chainId` and that no ETH value is sent with this SDK version.
- **Smart accounts support**: Compatible with smart accounts thanks to server-generated calldata.

API changes (breaking changes):
- **Args shape updated**
  - Removed: `initialPurchase`, and `currency: DeployCurrency`.
  - Renamed: `owners` to `additionalOwners` - adds additional owners to the coin, `payoutRecipient` to `overridePayoutReceipient` overrides the creator as the payout recipient.
  - Added: `creator: string`, `metadata: { type: 'RAW_URI'; uri: string }`, `currency: CoinCurrency`, `chainId: number`, `startingMarketCap: StartingMarketCap`, `skipMetadataValidation?: boolean`.
  - New enums: `CONTENT_COIN_CURRENCIES` (`CREATOR_COIN`, `ETH`, `ZORA`) and `StartingMarketCap` (`LOW`, `HIGH`).
- **Removed local pool/hook logic**: Internal pool config selection and prepurchase hook generation are removed and handled by the API.
- **Options updated**: `createCoin(..., options)` adds `skipValidateTransaction?: boolean` (skips a dry-run call and uses a fixed gas fallback) and continues to accept `account`.

Migration example
Before (main):
```ts
await createCoin(
  { name, symbol, uri, payoutRecipient, chainId, currency },
  walletClient,
  publicClient,
);
```

After (new):
```ts
await createCoin(
  {
    creator,
    name,
    symbol,
    metadata: { type: 'RAW_URI', uri },
    currency: CoinCurrency.CREATOR_COIN,
    chainId,
    startingMarketCap: StartingMarketCap.LOW,
    platformReferrerAddress,
  },
  walletClient,
  publicClient,
  { skipValidateTransaction: false },
);
```
