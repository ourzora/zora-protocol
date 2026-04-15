# Zora Coins SDK Skill

> SDK version: `@zoralabs/coins-sdk@0.5.2` | Network: Base mainnet (8453) | Testnet: Base Sepolia (84532)

You are an AI assistant helping developers build on the Zora Coins Protocol. Use this reference to guide implementation. Link to docs.zora.co for full code examples.

## When to Use What

| Goal                                   | Function / Section                           |
| -------------------------------------- | -------------------------------------------- |
| Deploy a new coin                      | `createCoin()` or `createCoinCall()`         |
| Upload metadata before creating        | `createMetadataBuilder()`                    |
| Buy or sell a coin                     | `tradeCoin()` or `createTradeCall()`         |
| Update coin metadata or payout address | `updateCoinURI()` or `setPayoutRecipient()`  |
| Look up a specific coin                | `getCoin()` or `getCoins()`                  |
| Get a user's holdings                  | `getProfileBalances()`                       |
| Browse trending / top coins            | Explore queries (`getCoinsTopGainers`, etc.) |
| Look up trend coins by ticker          | `getTrend()` or `getTrends()`                |
| Build in Python / Go / Ruby            | REST API                                     |
| Interact at the contract level         | Contract Reference section                   |

## Protocol Overview

ZORA Coins are ERC-20 media coins on Base (chain ID 8453). Every coin has a Uniswap V4 pool with locked liquidity, automatic reward distribution, and sniper protection.

**Chain support:**

- **Base mainnet (8453)** — Production. All features available.
- **Base Sepolia (84532)** — Testnet. `ZORA`, `CREATOR_COIN`, and `CREATOR_COIN_OR_ZORA` currencies are NOT available on Sepolia.

**Coin types:**

| Type         | Supply | Creator allocation     | Trading fee | Backing              |
| ------------ | ------ | ---------------------- | ----------- | -------------------- |
| Creator Coin | 1B     | 50% vests over 5 years | 1%          | ZORA or ETH          |
| Content Coin | 1B     | 10M immediate          | 1%          | Creator coin or ZORA |
| Trend Coin   | 1B     | None (100% to pool)    | 0.01%       | Pre-configured       |

**Fee distribution (creator/content coins, 1% total):**

| Recipient         | % of total fees |
| ----------------- | --------------- |
| Creator           | 50%             |
| Platform referral | 20%             |
| LP rewards        | 20%             |
| Trade referral    | 4%              |
| Protocol          | 5%              |
| Doppler           | 1%              |

All rewards are converted to the backing currency and distributed automatically on every swap.

**Sniper tax:** 99% fee at launch, decaying linearly to the base fee over 10 seconds.

## SDK Setup

Install: `npm install @zoralabs/coins-sdk viem`

Configure API key (recommended to avoid rate limiting and to get more accurate coin valuations via `getProfileBalances`):

```ts
import { setApiKey } from "@zoralabs/coins-sdk";
setApiKey("your-api-key-here");
```

Get an API key at https://zora.co/settings/developer

Full setup guide: https://docs.zora.co/coins/sdk

## Creating Coins

**Functions:** `createCoin()` (high-level, sends tx) and `createCoinCall()` (low-level, returns raw calldata)

**Parameters (`CreateCoinArgs`):**

| Parameter                 | Type                               | Required | Description                           |
| ------------------------- | ---------------------------------- | -------- | ------------------------------------- |
| `creator`                 | `Address`                          | Yes      | Creator wallet address                |
| `name`                    | `string`                           | Yes      | Coin name                             |
| `symbol`                  | `string`                           | Yes      | Trading symbol                        |
| `metadata`                | `{ type: "RAW_URI", uri: string }` | Yes      | Metadata URI (IPFS recommended)       |
| `currency`                | `ContentCoinCurrency`              | Yes      | See enum below                        |
| `chainId`                 | `number`                           | No       | Defaults to Base mainnet (8453)       |
| `startingMarketCap`       | `StartingMarketCap`                | No       | `LOW` (default) or `HIGH`             |
| `platformReferrer`        | `Address`                          | No       | Earns 20% of trading fees permanently |
| `additionalOwners`        | `Address[]`                        | No       | Additional owner addresses            |
| `payoutRecipientOverride` | `Address`                          | No       | Override payout address               |
| `skipMetadataValidation`  | `boolean`                          | No       | Skip URI validation (not recommended) |

**`ContentCoinCurrency` enum values:**

```ts
"CREATOR_COIN"; // Back with creator's coin
"CREATOR_COIN_OR_ZORA"; // Creator coin if exists, otherwise ZORA
"ZORA"; // Back with ZORA token
"ETH"; // Back with ETH
```

Note: `CREATOR_COIN`, `CREATOR_COIN_OR_ZORA`, and `ZORA` are NOT available on Base Sepolia.

**`StartingMarketCap` values:** `LOW` (default, most coins) or `HIGH` (known creators/brands, higher initial price to prevent sniping)

**Returns (`createCoin`):** `{ hash, receipt, address, deployment, chain }`

**Returns (`createCoinCall`):** `{ calls: [{ to, data, value }], predictedCoinAddress }`

**Metadata builder** — upload assets and produce a URI:

```ts
import {
  createMetadataBuilder,
  createZoraUploaderForCreator,
} from "@zoralabs/coins-sdk";

const { createMetadataParameters } = await createMetadataBuilder()
  .withName("My Coin")
  .withSymbol("MC")
  .withDescription("Description")
  .withImage(imageFile)
  .upload(createZoraUploaderForCreator(creatorAddress));
```

**Extract deployment from logs** (for custom tx flows):

```ts
import { getCoinCreateFromLogs } from "@zoralabs/coins-sdk";
const coinDeployment = getCoinCreateFromLogs(receipt);
```

Full docs: https://docs.zora.co/coins/sdk/create-coin
Metadata builder: https://docs.zora.co/coins/sdk/metadata-builder

## Trading Coins

**Functions:** `tradeCoin()` (full flow with permits) and `createTradeCall()` (direct ETH trades)

**Parameters (`TradeParameters`):**

| Parameter   | Type                                              | Required | Description                   |
| ----------- | ------------------------------------------------- | -------- | ----------------------------- |
| `sell`      | `{ type: "eth" }` or `{ type: "erc20", address }` | Yes      | Token to sell                 |
| `buy`       | `{ type: "eth" }` or `{ type: "erc20", address }` | Yes      | Token to buy                  |
| `amountIn`  | `bigint`                                          | Yes      | Amount in smallest unit       |
| `slippage`  | `number`                                          | No       | 0 to 0.99 (default 0.05 = 5%) |
| `sender`    | `Address`                                         | Yes      | Transaction sender            |
| `recipient` | `Address`                                         | No       | Defaults to sender            |

**Supported swaps:** ETH <-> ERC20, Creator Coin <-> Creator Coin, Content Coin <-> Creator Coin, ERC20 <-> ERC20

The SDK automatically handles permit signatures (EIP-2612 via permit2) to avoid separate approval transactions. Only EOA wallets are supported (smart wallet support coming soon).

**Network:** Base mainnet only.

Full docs: https://docs.zora.co/coins/sdk/trade-coin

## Updating Coins

**Functions:** `updateCoinURI()` and `setPayoutRecipient()` (owner-only)

- `updateCoinURI({ coin, newURI })` — Update metadata URI (IPFS preferred)
- `setPayoutRecipient({ coin, newPayoutRecipient })` — Change reward recipient

Non-owners receive an `OnlyOwner` revert.

Full docs: https://docs.zora.co/coins/sdk/update-coin

## Querying Coins

### Coin data

| Function                                                | Description         | Key params                        |
| ------------------------------------------------------- | ------------------- | --------------------------------- |
| `getCoin({ address, chain? })`                          | Single coin details | `address`, `chain` (default 8453) |
| `getCoins({ coinAddresses, chainId? })`                 | Batch coin details  | Array of addresses                |
| `getCoinComments({ address, chain?, after?, count? })`  | Coin comments       | Pagination via `after` cursor     |
| `getCoinHolders({ address, chainId?, after?, count? })` | Coin holders list   | Pagination via `after` cursor     |
| `getCoinSwaps({ address, chain?, after?, first? })`     | Trade history       | Pagination via `after` cursor     |

### Profile data

| Function                                          | Description           | Key params                    |
| ------------------------------------------------- | --------------------- | ----------------------------- |
| `getProfile({ address })`                         | User profile          | Wallet address or handle      |
| `getProfileBalances({ address, after?, count? })` | User's coin balances  | Pagination via `after` cursor |
| `getProfileCoins({ identifier, count?, after? })` | Coins created by user | Pagination via `after` cursor |

### Explore

| Function                        | Description                         |
| ------------------------------- | ----------------------------------- |
| `getCoinsTopGainers()`          | Largest 24h market cap increases    |
| `getCoinsTopVolume24h()`        | Highest 24h trading volume          |
| `getCoinsMostValuable()`        | Highest market cap                  |
| `getCoinsNew()`                 | Most recently created               |
| `getCoinsLastTraded()`          | Most recent trading activity        |
| `getCoinsLastTradedUnique()`    | Most recent unique trader activity  |
| `getCreatorCoins()`             | Coins from new creators             |
| `getMostValuableCreatorCoins()` | Highest-valued creator coins        |
| `getMostValuableAll()`          | Most valuable across all coin types |

All explore functions accept optional `count` and `after` for cursor-based pagination.

### Trend coins

| Function               | Description                 | Key params       |
| ---------------------- | --------------------------- | ---------------- |
| `getTrend({ ticker })` | Single trend coin by ticker | Case-insensitive |
| `getTrends({ name })`  | Search trend coins by name  | With pagination  |

Full docs: https://docs.zora.co/coins/sdk/queries

## Common Patterns

### Create a coin with metadata upload

```ts
// 1. Build and upload metadata
const { createMetadataParameters } = await createMetadataBuilder()
  .withName("My Coin")
  .withSymbol("MC")
  .withDescription("A coin")
  .withImage(imageFile)
  .upload(createZoraUploaderForCreator(creatorAddress));

// 2. Create the coin (spreads name, symbol, uri from metadata)
const result = await createCoin({
  call: {
    ...createMetadataParameters,
    creator: creatorAddress,
    currency: "ZORA",
    chainId: 8453,
  },
  walletClient,
  publicClient,
});

// 3. Verify deployment
const coin = await getCoin({ address: result.address });
```

### Look up a coin, then buy it

```ts
// 1. Look up the coin
const { data } = await getCoin({ address: coinAddress });
console.log(data.zora20Token.marketCap);

// 2. Buy with ETH
const receipt = await tradeCoin({
  tradeParameters: {
    sell: { type: "eth" },
    buy: { type: "erc20", address: coinAddress },
    amountIn: parseEther("0.01"),
    slippage: 0.05,
    sender: account.address,
  },
  walletClient,
  account,
  publicClient,
});
```

### Paginate through results

```ts
let cursor = null;
const allItems = [];
do {
  const response = await getCoinComments({
    address: coinAddress,
    count: 20,
    after: cursor,
  });
  allItems.push(
    ...response.data.zora20Token.zoraComments.edges.map((e) => e.node),
  );
  cursor = response.pagination?.cursor;
} while (cursor);
```

## Error Handling

| Error                      | Cause                                             | Recovery                                                                           |
| -------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Transaction reverted       | Insufficient funds, slippage exceeded, sniper tax | Check balance, increase slippage, wait 10s after coin creation                     |
| `OnlyOwner` revert         | Calling update functions without ownership        | Verify caller is in the coin's owners array                                        |
| `TickerAlreadyUsed` revert | Deploying trend coin with existing ticker         | Trend coin tickers are globally unique and case-insensitive                        |
| Metadata validation error  | Invalid URI or missing fields                     | Use `validateMetadataURIContent()` to check, or set `skipMetadataValidation: true` |
| Rate limit (429)           | Too many API requests without key                 | Set API key via `setApiKey()`                                                      |
| Permit signature failure   | Smart wallet or non-EOA signer                    | Only EOA wallets support permits currently                                         |

## REST API

For non-TypeScript languages (Python, Go, Ruby, etc.), use the REST API:

- Interactive docs: https://api-sdk.zora.engineering/docs
- Authentication: Pass API key via `api-key` header
- Endpoints cover coin data, profile data, and explore feeds

Full docs: https://docs.zora.co/coins/sdk/public-rest-api

## Contract Reference

**Factory address (Base & Base Sepolia):** `0x777777751622c0d3258f214F9DF38E35BF45baF3`

**Key factory functions:**

- `deploy()` — Deploy content or creator coins with full customization
- `deployCreatorCoin()` — Simplified creator coin deployment (first call per address is the official creator coin)
- `deployTrendCoin(symbol)` — Deploy trend coins with globally unique, case-insensitive tickers
- `coinAddress()` / `trendCoinAddress()` — Predict deployment address before transaction

**Hook system:** All coins use the unified `ZoraV4CoinHook` on Uniswap V4 which handles fee collection, reward distribution, and sniper tax enforcement.

**Earning referral rewards:**

- Platform referral: Set `platformReferrer` at coin deployment to earn 20% of all future trades
- Trade referral: Encode your address in swap `hookData` to earn 4% per trade

Full docs: https://docs.zora.co/coins/contracts

## Links

- SDK docs: https://docs.zora.co/coins/sdk
- Contract docs: https://docs.zora.co/coins/contracts
- API key: https://zora.co/settings/developer
- REST API: https://api-sdk.zora.engineering/docs
- GitHub: https://github.com/ourzora/zora-protocol
- npm: https://www.npmjs.com/package/@zoralabs/coins-sdk
