---
"@zoralabs/coins-sdk": minor
---

Creator coins can only be created via the Zora app. This SDK allows you to create content coins paired with existing creator coins.

Create content flow uses server-generated calldata via the SDK API.

- **Server-generated calldata**: `createCoinCall` now requests calldata from the SDK API and returns an array of transaction parameters `{ to, data, value }[]` instead of a Viem `SimulateContractParameters` object.
- **Direct transaction sending**: `createCoin` constructs and sends the transaction using `walletClient.sendTransaction` with manual gas estimation and an option to skip validation.
- **Sanity checks**: Ensures the call targets the expected factory for the specified `chainId` and that no ETH value is sent with this SDK version.
- **Smart accounts support**: Compatible with smart accounts thanks to server-generated calldata.

API changes (breaking changes):
- **Args shape updated**
  - Removed: `initialPurchase`, and `currency: DeployCurrency`.
  - Renamed: `owners` to `additionalOwners` - adds additional owners to the coin, `payoutRecipient` to `payoutRecipientOverride` overrides the creator as the payout recipient.
  - Added: `creator: string`, `metadata: { type: 'RAW_URI'; uri: string }`, `currency: ContentCoinCurrency`, `chainId?: number`, `startingMarketCap?: StartingMarketCap`, `platformReferrer?: string`, `skipMetadataValidation?: boolean`.
  - New types/constants: `ContentCoinCurrency` with runtime constants `CreateConstants.ContentCoinCurrencies` (`CREATOR_COIN`, `ETH`, `ZORA`, `CREATOR_COIN_OR_ZORA`) and `StartingMarketCap` with runtime constants `CreateConstants.StartingMarketCaps` (`LOW`, `HIGH`).
- **Removed local pool/hook logic**: Internal pool config selection and prepurchase hook generation are removed and handled by the API.
- **Options updated**: `createCoin({ ..., options })` adds `skipValidateTransaction?: boolean` (skips a dry-run call and uses a fixed gas fallback) and continues to accept `account`.

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
await createCoin({
  call: {
    creator,
    name,
    symbol,
    metadata: { type: 'RAW_URI', uri },
    currency: CreateConstants.ContentCoinCurrencies.CREATOR_COIN,
    chainId,
    startingMarketCap: CreateConstants.StartingMarketCaps.LOW,
    platformReferrer,
  },
  walletClient,
  publicClient,
  options: { skipValidateTransaction: false },
});
```
