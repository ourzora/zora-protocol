# Coins SDK

The `@zoralabs/coins-sdk` package is currently a prerelease SDK.

This SDK is based off of viem v2 and exposes both functions to get the viem call to use with WAGMI, and also functions that complete the actions using the simulateContract and writeContract calls. Many reasonable defaults are set for fields, so read the action files and types to determine which parameters are needed for your actions.

Devs can input their addresses in `platformReferrer` and `traderReferrer` fields to earn trade and create referral fees for their platform.

This prerelease SDK has two main categories of functionality: Onchain Actions and Queries.

All the SDK functions are accessible from the main export (for example: `import {createCoin, getCoin} from "@zoralabs/coins-sdk"`).

## Table of Contents

### Onchain Actions


- [createCoin](#1-createcoin-creates-a-new-coin-with-the-given-parameters-to-trade)
- [tradeCoin](#2-tradecoin-buys-or-sells-an-existing-coin)
- [updateCoinURI](#3-updatecoinuri-updates-the-uri-for-an-existing-coin)

### Queries


- [On chain queries](#onchain-queries)
  - [getOnchainCoinDetails](#1-getonchaincoindetails-gets-details-for-the-given-coin-from-the-blockchain)
- [API Queries](#3-api-queries)
  - [API Key](#2-api-key)
  - [Cursor Pagination](#cursor-pagination)
  - Queries
    - [getCoin](#getcoin-get-details-for-a-specific-coin)
    - [getCoins](#getcoins-get-details-for-multiple-coins)
    - [getCoinComments](#getcoincomments-get-comments-for-a-coin)
    - [getProfile](#getprofile-get-profile-information)
    - [getProfileOwned](#getprofileowned-get-coins-owned-by-a-profile)
    - [getCoinsTopGainers](#getcoinstopgainers)
    - [getCoinsTopVolume24h](#getcoinstopvolume24h)
    - [getCoinsMostValuable](#getcoinsmostvaluable)
    - [getCoinsNew](#getcoinsnew)
    - [getCoinsLastTraded](#getcoinslasttraded)
    - [getCoinsLastTradedUnique](#getcoinslasttradedunique)

## Onchain Actions

These are functions that interact directly with the blockchain and require transaction signing.

### 1. `createCoin`: Creates a new coin with the given parameters to trade.

**Key Parameters:**

- `name`: The name of the new coin.
- `symbol`: The symbol for the new coin.
- `uri`: The URI for the coin metadata.
- `owners`: An array of owner addresses. (Optional)
- `payoutRecipient`: The address that will receive the payout.
- `platformReferrer`: The referrer address for the platform that earns referral fees. (Optional)
- `initialPurchaseWei`: The initial purchase amount in Wei. (Optional)
**Key Parameters:**

- `name`: The name of the new coin.
- `symbol`: The symbol for the new coin.
- `uri`: The URI for the coin metadata.
- `owners`: An array of owner addresses. (Optional)
- `payoutRecipient`: The address that will receive the payout.
- `platformReferrer`: The referrer address for the platform that earns referral fees. (Optional)
- `initialPurchaseWei`: The initial purchase amount in Wei. (Optional)

**Usage:**

```typescript
const createCoinParams = {
  name: "MyCoin",
  symbol: "MYC",
  uri: "https://example.com/metadata",
  payoutRecipient: "0xRecipientAddress",
};
**Usage:**

```typescript
const createCoinParams = {
  name: "MyCoin",
  symbol: "MYC",
  uri: "https://example.com/metadata",
  payoutRecipient: "0xRecipientAddress",
};

const result = await createCoin(createCoinParams, walletClient, publicClient);
console.log(result);
```
const result = await createCoin(createCoinParams, walletClient, publicClient);
console.log(result);
```

**Lower Level Call Method with WAGMI:**
Use the `createCoinCall` function to get the contract call parameters and then use WAGMI's `useContractWrite` hook.
**Lower Level Call Method with WAGMI:**
Use the `createCoinCall` function to get the contract call parameters and then use WAGMI's `useContractWrite` hook.

```typescript
const createCoinParams = {
  name: "MyCoin",
  symbol: "MYC",
  uri: "https://example.com/metadata",
  payoutRecipient: "0xRecipientAddress",
};
```typescript
const createCoinParams = {
  name: "MyCoin",
  symbol: "MYC",
  uri: "https://example.com/metadata",
  payoutRecipient: "0xRecipientAddress",
};

const { config } = createCoinCall(createCoinParams);
const { write } = useContractWrite(config);
const { config } = createCoinCall(createCoinParams);
const { write } = useContractWrite(config);

write(); // Execute the contract write
// the receipt can be parsed from `getCoinCreateFromLogs(receipt.logs)`
```
write(); // Execute the contract write
// the receipt can be parsed from `getCoinCreateFromLogs(receipt.logs)`
```

### 2. `tradeCoin`: Buys or sells an existing coin.

**Key Parameters:**

- `direction`: The trade direction, either 'buy' or 'sell'.
- `target`: The target coin contract address.
- `args`: The trade arguments.
  - `recipient`: The recipient of the trade output.
  - `orderSize`: The size of the order.
  - `minAmountOut`: The minimum amount to receive. (Optional)
  - `sqrtPriceLimitX96`: The price limit for the trade. (Optional)
  - `tradeReferrer`: The platform referrer fee recipient address for the trade. (Optional)
**Key Parameters:**

- `direction`: The trade direction, either 'buy' or 'sell'.
- `target`: The target coin contract address.
- `args`: The trade arguments.
  - `recipient`: The recipient of the trade output.
  - `orderSize`: The size of the order.
  - `minAmountOut`: The minimum amount to receive. (Optional)
  - `sqrtPriceLimitX96`: The price limit for the trade. (Optional)
  - `tradeReferrer`: The platform referrer fee recipient address for the trade. (Optional)

**Usage:**

```typescript
const tradeParams = {
  direction: "buy",
  target: "0xTargetAddress",
  args: {
    recipient: "0xRecipientAddress",
    orderSize: 1000n,
  },
};
**Usage:**

```typescript
const tradeParams = {
  direction: "buy",
  target: "0xTargetAddress",
  args: {
    recipient: "0xRecipientAddress",
    orderSize: 1000n,
  },
};

const result = await tradeCoin(tradeParams, walletClient, publicClient);
console.log(result);
```
const result = await tradeCoin(tradeParams, walletClient, publicClient);
console.log(result);
```

**Lower Level Call Method with WAGMI:**
Use the `tradeCoinCall` function to get the contract call parameters and then use WAGMI's `useContractWrite` hook.
**Lower Level Call Method with WAGMI:**
Use the `tradeCoinCall` function to get the contract call parameters and then use WAGMI's `useContractWrite` hook.

```typescript
const tradeParams = {
  direction: "buy",
  target: "0xTargetAddress",
  args: {
    recipient: "0xRecipientAddress",
    orderSize: 1000n,
  },
};
```typescript
const tradeParams = {
  direction: "buy",
  target: "0xTargetAddress",
  args: {
    recipient: "0xRecipientAddress",
    orderSize: 1000n,
  },
};

const { config } = tradeCoinCall(tradeParams);
const { write } = useContractWrite(config);
const { config } = tradeCoinCall(tradeParams);
const { write } = useContractWrite(config);

write(); // Execute the contract write
// the receipt can be parsed from `getTradeFromLogs(receipt.logs)`
```
write(); // Execute the contract write
// the receipt can be parsed from `getTradeFromLogs(receipt.logs)`
```

### 3. `updateCoinURI`: Updates the URI for an existing coin.

**Key Parameters:**

- `coin`: The coin contract address.
- `newURI`: The new URI for the coin metadata (must start with "ipfs://").
**Key Parameters:**

- `coin`: The coin contract address.
- `newURI`: The new URI for the coin metadata (must start with "ipfs://").

**Usage:**

```typescript
const updateParams = {
  coin: "0xCoinAddress",
  newURI: "ipfs://new-metadata-uri",
};
**Usage:**

```typescript
const updateParams = {
  coin: "0xCoinAddress",
  newURI: "ipfs://new-metadata-uri",
};

const result = await updateCoinURI(updateParams, walletClient, publicClient);
console.log(result);
```
const result = await updateCoinURI(updateParams, walletClient, publicClient);
console.log(result);
```

**Lower Level Call Method with WAGMI:**

```typescript
const updateParams = {
  coin: "0xCoinAddress",
  newURI: "ipfs://new-metadata-uri",
};
**Lower Level Call Method with WAGMI:**

```typescript
const updateParams = {
  coin: "0xCoinAddress",
  newURI: "ipfs://new-metadata-uri",
};

const { config } = updateCoinURICall(updateParams);
const { write } = useContractWrite(config);
const { config } = updateCoinURICall(updateParams);
const { write } = useContractWrite(config);

write(); // Execute the contract write
```
write(); // Execute the contract write
```

## Onchain Queries

These are functions that read data from the blockchain or API without requiring transaction signing.

### 1. `getOnchainCoinDetails`: Gets details for the given coin from the blockchain.

This query retrieves the most up-to-date coin information directly from the blockchain.
It is strongly recommended to use the other API queries to fetch this information if possible.

**Key Parameters:**

- `coin`: The coin contract address.
- `user`: The user address to check balance for. (Optional)
- `publicClient`: The viem public client instance.
**Key Parameters:**

- `coin`: The coin contract address.
- `user`: The user address to check balance for. (Optional)
- `publicClient`: The viem public client instance.

**Return Value:**

- `balance`: The user's balance of the coin.
- `marketCap`: The market cap of the coin.
- `liquidity`: The liquidity of the coin.
- `pool`: Pool address.
- `poolState`: Current state of the UniswapV3 pool.
- `owners`: List of owners for the coin.
- `payoutRecipient`: The payout recipient address.
**Return Value:**

- `balance`: The user's balance of the coin.
- `marketCap`: The market cap of the coin.
- `liquidity`: The liquidity of the coin.
- `pool`: Pool address.
- `poolState`: Current state of the UniswapV3 pool.
- `owners`: List of owners for the coin.
- `payoutRecipient`: The payout recipient address.

### 2. API Queries

These functions interact with the Zora API to fetch additional data:
These functions interact with the Zora API to fetch additional data:

#### API Key
#### API Key

To get a higher rate limit and fully use the zora API, an API key is required.
To get a higher rate limit and fully use the zora API, an API key is required.

To set the API key, you can use the `setApiKey` function which will apply your API key to all requests.
To set the API key, you can use the `setApiKey` function which will apply your API key to all requests.

```typescript
setApiKey("your-api-key");
```
```typescript
setApiKey("your-api-key");
```

Please DM the Zora team to get the API key.
Please DM the Zora team to get the API key.

These queries allow non-api-key access for reasonable development usage.
These queries allow non-api-key access for reasonable development usage.

#### Cursor Pagination
#### Cursor Pagination

Many queries support cursor-based pagination using the `after` parameter. To paginate through results:
Many queries support cursor-based pagination using the `after` parameter. To paginate through results:

1.  Make your initial query without an `after` parameter
2.  From the response, get the `endCursor` from the `pageInfo` object
3.  Pass this `endCursor` as the `after` parameter in your next query
1.  Make your initial query without an `after` parameter
2.  From the response, get the `endCursor` from the `pageInfo` object
3.  Pass this `endCursor` as the `after` parameter in your next query

**Example:**

```typescript
// First page
const firstPage = await getCoinsTopGainers({
  count: 10,
});

// Get the cursor for the next page
const nextCursor = firstPage.exploreList?.pageInfo?.endCursor;

// Fetch next page using the cursor
if (nextCursor) {
  const nextPage = await getCoinsTopGainers({
    count: 10,
    after: nextCursor,
  });
}
```
**Example:**

```typescript
// First page
const firstPage = await getCoinsTopGainers({
  count: 10,
});

// Get the cursor for the next page
const nextCursor = firstPage.exploreList?.pageInfo?.endCursor;

// Fetch next page using the cursor
if (nextCursor) {
  const nextPage = await getCoinsTopGainers({
    count: 10,
    after: nextCursor,
  });
}
```

**Complete Pagination Example:**

```typescript
async function fetchAllTopGainers() {
  const allResults = [];
  let hasNextPage = true;
  let cursor: string | undefined;

  while (hasNextPage) {
    const response = await getCoinsTopGainers({
      count: 10,
      after: cursor,
    });

    const { edges, pageInfo } = response.exploreList || {};

    if (edges) {
      allResults.push(...edges.map((edge) => edge.node));
    }

    hasNextPage = pageInfo?.hasNextPage || false;
    cursor = pageInfo?.endCursor;
  }

  return allResults;
}
```
**Complete Pagination Example:**

```typescript
async function fetchAllTopGainers() {
  const allResults = [];
  let hasNextPage = true;
  let cursor: string | undefined;

  while (hasNextPage) {
    const response = await getCoinsTopGainers({
      count: 10,
      after: cursor,
    });

    const { edges, pageInfo } = response.exploreList || {};

    if (edges) {
      allResults.push(...edges.map((edge) => edge.node));
    }

    hasNextPage = pageInfo?.hasNextPage || false;
    cursor = pageInfo?.endCursor;
  }

  return allResults;
}
```

This pagination pattern works for all queries that return `pageInfo` with `endCursor` and `hasNextPage`, including:

- All explore queries
- `getCoinComments`
- `getProfileOwned`

## All API Queries
This pagination pattern works for all queries that return `pageInfo` with `endCursor` and `hasNextPage`, including:

- All explore queries
- `getCoinComments`
- `getProfileOwned`

## All API Queries

#### `getCoin`: Get details for a specific coin

**Parameters:**

- `address`: The coin contract address
- `chain`: (Optional) The chain ID
#### `getCoin`: Get details for a specific coin

**Parameters:**

- `address`: The coin contract address
- `chain`: (Optional) The chain ID

**Returns:**

```typescript
{
  zora20Token?: {
    id?: string;
    name?: string;
    description?: string;
    address?: string;
    symbol?: string;
    totalSupply?: string;
    totalVolume?: string;
    volume24h?: string;
    createdAt?: string;
    creatorAddress?: string;
    creatorEarnings?: Array<{
      amount?: {
        currency?: { address?: string };
        amountRaw?: string;
        amountDecimal?: number;
      };
      amountUsd?: string;
    }>;
    marketCap?: string;
    marketCapDelta24h?: string;
    chainId?: number;
    creatorProfile?: string;
    handle?: string;
    avatar?: {
      previewImage?: string;
      blurhash?: string;
      small?: string;
    };
    media?: {
      mimeType?: string;
      originalUri?: string;
      format?: string;
      previewImage?: string;
      medium?: string;
      blurhash?: string;
    };
    transfers?: { count?: number };
    uniqueHolders?: number;
  }
}
```
**Returns:**

```typescript
{
  zora20Token?: {
    id?: string;
    name?: string;
    description?: string;
    address?: string;
    symbol?: string;
    totalSupply?: string;
    totalVolume?: string;
    volume24h?: string;
    createdAt?: string;
    creatorAddress?: string;
    creatorEarnings?: Array<{
      amount?: {
        currency?: { address?: string };
        amountRaw?: string;
        amountDecimal?: number;
      };
      amountUsd?: string;
    }>;
    marketCap?: string;
    marketCapDelta24h?: string;
    chainId?: number;
    creatorProfile?: string;
    handle?: string;
    avatar?: {
      previewImage?: string;
      blurhash?: string;
      small?: string;
    };
    media?: {
      mimeType?: string;
      originalUri?: string;
      format?: string;
      previewImage?: string;
      medium?: string;
      blurhash?: string;
    };
    transfers?: { count?: number };
    uniqueHolders?: number;
  }
}
```

#### `getCoins`: Get details for multiple coins

**Parameters:**

- `coins`: Array of coin objects with:
  - `chainId`: (Optional) The chain ID
  - `collectionAddress`: The coin contract address
#### `getCoins`: Get details for multiple coins

**Parameters:**

- `coins`: Array of coin objects with:
  - `chainId`: (Optional) The chain ID
  - `collectionAddress`: The coin contract address

**Returns:** Array of coin details in the same format as `getCoin`
**Returns:** Array of coin details in the same format as `getCoin`

#### `getCoinComments`: Get comments for a coin

**Parameters:**

- `address`: The coin contract address
- `chain`: (Optional) The chain ID
- `after`: (Optional) Pagination cursor
- `count`: (Optional) Number of comments to return
#### `getCoinComments`: Get comments for a coin

**Parameters:**

- `address`: The coin contract address
- `chain`: (Optional) The chain ID
- `after`: (Optional) Pagination cursor
- `count`: (Optional) Number of comments to return

**Returns:**

```typescript
{
  zora20Token?: {
    zoraComments?: {
      pageInfo?: {
        endCursor?: string;
        hasNextPage?: boolean;
      };
      count?: number;
      edges?: Array<{
        node?: string;
        txHash?: string;
        comment?: string;
        userAddress?: string;
        timestamp?: number;
        userProfile?: string;
        id?: string;
        handle?: string;
        avatar?: {
          previewImage?: string;
          blurhash?: string;
          small?: string;
        };
        replies?: {
          count?: number;
          edges?: Array<{
            node?: {
              txHash?: string;
              comment?: string;
              userAddress?: string;
              timestamp?: number;
              userProfile?: string;
              id?: string;
              handle?: string;
              avatar?: {
                previewImage?: string;
                blurhash?: string;
                small?: string;
              };
            };
          }>;
        };
      }>;
    };
  }
}
```
**Returns:**

```typescript
{
  zora20Token?: {
    zoraComments?: {
      pageInfo?: {
        endCursor?: string;
        hasNextPage?: boolean;
      };
      count?: number;
      edges?: Array<{
        node?: string;
        txHash?: string;
        comment?: string;
        userAddress?: string;
        timestamp?: number;
        userProfile?: string;
        id?: string;
        handle?: string;
        avatar?: {
          previewImage?: string;
          blurhash?: string;
          small?: string;
        };
        replies?: {
          count?: number;
          edges?: Array<{
            node?: {
              txHash?: string;
              comment?: string;
              userAddress?: string;
              timestamp?: number;
              userProfile?: string;
              id?: string;
              handle?: string;
              avatar?: {
                previewImage?: string;
                blurhash?: string;
                small?: string;
              };
            };
          }>;
        };
      }>;
    };
  }
}
```

#### `getProfile`: Get profile information

**Parameters:**

- `identifier`: The profile identifier (username, handle, or address)
#### `getProfile`: Get profile information

**Parameters:**

- `identifier`: The profile identifier (username, handle, or address)

**Returns:**

```typescript
{
  profile?: string;
  id?: string;
  handle?: string;
  avatar?: {
    small?: string;
    medium?: string;
    blurhash?: string;
  };
  username?: string;
  displayName?: string;
  bio?: string;
  website?: string;
  publicWallet?: {
    walletAddress?: string;
  };
  linkedWallets?: {
    edges?: Array<{
      node?: {
        walletType?: "PRIVY" | "EXTERNAL" | "SMART_WALLET";
        walletAddress?: string;
      };
    }>;
  };
}
```
**Returns:**

```typescript
{
  profile?: string;
  id?: string;
  handle?: string;
  avatar?: {
    small?: string;
    medium?: string;
    blurhash?: string;
  };
  username?: string;
  displayName?: string;
  bio?: string;
  website?: string;
  publicWallet?: {
    walletAddress?: string;
  };
  linkedWallets?: {
    edges?: Array<{
      node?: {
        walletType?: "PRIVY" | "EXTERNAL" | "SMART_WALLET";
        walletAddress?: string;
      };
    }>;
  };
}
```

#### `getProfileOwned`: Get coins owned by a profile

**Parameters:**

- `identifier`: The profile identifier (username, handle, or address)
- `count`: (Optional) Number of items to return
- `after`: (Optional) Pagination cursor
- `chainIds`: (Optional) Array of chain IDs to filter by
#### `getProfileOwned`: Get coins owned by a profile

**Parameters:**

- `identifier`: The profile identifier (username, handle, or address)
- `count`: (Optional) Number of items to return
- `after`: (Optional) Pagination cursor
- `chainIds`: (Optional) Array of chain IDs to filter by

**Returns:**

```typescript
{
  profile?: string;
  id?: string;
  handle?: string;
  avatar?: {
    previewImage?: string;
    blurhash?: string;
    small?: string;
  };
  coinBalances?: {
    count?: number;
    edges?: Array<{
      node?: {
        balance?: string;
        id?: string;
        coin?: {
          // Same coin details as getCoin
        };
      };
    }>;
    pageInfo?: {
      hasNextPage?: boolean;
      endCursor?: string;
    };
  };
}
```
**Returns:**

```typescript
{
  profile?: string;
  id?: string;
  handle?: string;
  avatar?: {
    previewImage?: string;
    blurhash?: string;
    small?: string;
  };
  coinBalances?: {
    count?: number;
    edges?: Array<{
      node?: {
        balance?: string;
        id?: string;
        coin?: {
          // Same coin details as getCoin
        };
      };
    }>;
    pageInfo?: {
      hasNextPage?: boolean;
      endCursor?: string;
    };
  };
}
```

#### `getCoinsTopGainers`: Get top gaining coins


**Parameters:**

- `count`: (Optional) Number of items to return, type: `number`
- `after`: (Optional) Pagination cursor, type: `string`

**Request Type:**


```typescript
// Types from @zoralabs/coins-sdk
export type RequestOptionsType = Omit<GetExploreData, "query">;

export type QueryInnerType = {
  query: {
    count?: number;
    after?: string;
  };
};
```

**Return Type:**

```typescript
{
  exploreList?: {
    edges?: Array<{
      node?: {
        id?: string;
        name?: string;
        description?: string;
        address?: string;
        symbol?: string;
        totalSupply?: string;
        totalVolume?: string;
        volume24h?: string;
        createdAt?: string;
        creatorAddress?: string;
        creatorEarnings?: Array<{...}>;
        marketCap?: string;
        marketCapDelta24h?: string;
        chainId?: number;
        creatorProfile?: string;
        handle?: string;
        avatar?: {...};
        media?: {...};
        transfers?: { count?: number };
        uniqueHolders?: number;
      };
      cursor?: string;
    }>;
    pageInfo?: {
      endCursor?: string;
      hasNextPage?: boolean;
    };
  };
}
```

#### `getCoinsTopVolume24h`: Get coins with highest 24h volume


**Parameters:**

- `count`: (Optional) Number of items to return, type: `number`
- `after`: (Optional) Pagination cursor, type: `string`

**Request Type:**

```typescript
function getCoinsTopVolume24h(
  query: QueryInnerType,
  options?: RequestOptionsType,
): Promise<ExploreResponse>;
```

**Request Type:** Same as `getCoinsTopGainers`
**Return Type:** Same as `getCoinsTopGainers`

#### `getCoinsMostValuable`: Get most valuable coins


**Parameters:**

- `count`: (Optional) Number of items to return, type: `number`
- `after`: (Optional) Pagination cursor, type: `string`

**Request Type:**

```typescript
function getCoinsMostValuable(
  query: QueryInnerType,
  options?: RequestOptionsType,
): Promise<ExploreResponse>;
```

**Request Type:** Same as `getCoinsTopGainers`
**Return Type:** Same as `getCoinsTopGainers`

#### `getCoinsNew`: Get newly created coins


**Parameters:**

- `count`: (Optional) Number of items to return, type: `number`
- `after`: (Optional) Pagination cursor, type: `string`

**Request Type:**

```typescript
function getCoinsNew(
  query: QueryInnerType,
  options?: RequestOptionsType,
): Promise<ExploreResponse>;
```

**Request Type:** Same as `getCoinsTopGainers`
**Return Type:** Same as `getCoinsTopGainers`

#### `getCoinsLastTraded`: Get recently traded coins


**Parameters:**

- `count`: (Optional) Number of items to return, type: `number`
- `after`: (Optional) Pagination cursor, type: `string`

**Request Type:**

```typescript
function getCoinsLastTraded(
  query: QueryInnerType,
  options?: RequestOptionsType,
): Promise<ExploreResponse>;
```

**Request Type:** Same as `getCoinsTopGainers`
**Return Type:** Same as `getCoinsTopGainers`

#### `getCoinsLastTradedUnique`: Get recently traded unique coins


**Parameters:**

- `count`: (Optional) Number of items to return, type: `number`
- `after`: (Optional) Pagination cursor, type: `string`

**Request Type:**

```typescript
function getCoinsLastTradedUnique(
  query: QueryInnerType,
  options?: RequestOptionsType,
): Promise<ExploreResponse>;
```

**Request Type:** Same as `getCoinsTopGainers`
**Return Type:** Same as `getCoinsTopGainers`
