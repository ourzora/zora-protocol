# Creating Coins

The Coins SDK provides a set of functions to create new coins on the Zora protocol. This page details the process of creating a new coin, the parameters involved, and code examples to help you get started.

## Overview

Creating a coin involves deploying a new ERC20 contract with the necessary Zora protocol integrations. The `createCoin` function handles this process and provides access to the deployed contract.

## Parameters

To create a new coin, you'll need to provide the following parameters:

```ts twoslash
import { Address } from "viem";
import { DeployCurrency } from "@zoralabs/coins-sdk";

type CreateCoinArgs = {
  name: string;             // The name of the coin (e.g., "My Awesome Coin")
  symbol: string;           // The trading symbol for the coin (e.g., "MAC")
  uri: string;              // Metadata URI (an IPFS URI is recommended)
  chainId?: number;         // The chain ID (defaults to base mainnet)
  owners?: Address[];       // Optional array of owner addresses, defaults to [payoutRecipient]
  payoutRecipient: Address; // Address that receives creator earnings
  platformReferrer?: Address; // Optional platform referrer address, earns referral fees
  // DeployCurrency.ETH or DeployCurrency.ZORA
  currency?: DeployCurrency; // Optional currency for trading (ETH or ZORA)
}
```

### Metadata

The `uri` parameter structure is described in the [Metadata](/coins/contracts/metadata) section.

### Currency

The `currency` parameter determines which token will be used for the trading pair.

```ts
enum DeployCurrency {
  ZORA = 1,
  ETH = 2,
}
```

By default:
- On Base mainnet, ZORA is used as the default currency
- On other chains, ETH is used as the default currency

Note that ZORA is not supported on Base Sepolia.

### Chain ID

The `chainId` parameter defaults to Base mainnet. Make sure it matches the chain you're deploying to.

### More Information

Further contract details can be found in the [Factory Contract](/coins/contracts/factory) section and the [Coin Contract](/coins/contracts/coin) section.


## Usage

### Basic Creation

```ts twoslash
import { createCoin, DeployCurrency } from "@zoralabs/coins-sdk";
import { Hex, createWalletClient, createPublicClient, http, Address } from "viem";
import { base } from "viem/chains";

// Set up viem clients
const publicClient = createPublicClient({
  chain: base,
  transport: http("<RPC_URL>"),
});

const walletClient = createWalletClient({
  account: "0x<YOUR_ACCOUNT>" as Hex,
  chain: base,
  transport: http("<RPC_URL>"),
});

// Define coin parameters
const coinParams = {
  name: "My Awesome Coin",
  symbol: "MAC",
  uri: "ipfs://bafybeigoxzqzbnxsn35vq7lls3ljxdcwjafxvbvkivprsodzrptpiguysy",
  payoutRecipient: "0xYourAddress" as Address,
  platformReferrer: "0xOptionalPlatformReferrerAddress" as Address, // Optional
  chainId: base.id, // Optional: defaults to base.id
  currency: DeployCurrency.ZORA, // Optional: ZORA or ETH
};

// Create the coin
async function createMyCoin() {
  try {
    const result = await createCoin(coinParams, walletClient, publicClient, {
      gasMultiplier: 120, // Optional: Add 20% buffer to gas (defaults to 100%)
      // account: customAccount, // Optional: Override the wallet client account
    });
    
    console.log("Transaction hash:", result.hash);
    console.log("Coin address:", result.address);
    console.log("Deployment details:", result.deployment);
    
    return result;
  } catch (error) {
    console.error("Error creating coin:", error);
    throw error;
  }
}
```

### Using with WAGMI

If you're using WAGMI in your frontend application, you can use the lower-level `createCoinCall` function:

```typescript
import * as React from "react";
import { createCoinCall, DeployCurrency } from "@zoralabs/coins-sdk";
import { Address } from "viem";
import { useWriteContract, useSimulateContract } from "wagmi";

// Define coin parameters
const coinParams = {
  name: "My Awesome Coin",
  symbol: "MAC",
  uri: "ipfs://bafybeigoxzqzbnxsn35vq7lls3ljxdcwjafxvbvkivprsodzrptpiguysy",
  payoutRecipient: "0xYourAddress" as Address,
  platformReferrer: "0xOptionalPlatformReferrerAddress" as Address,
  // chainId: base.id, // Optional: defaults to base.id
  // currency: DeployCurrency.ZORA, // Optional: ZORA or ETH
};

// Create configuration for wagmi
const contractCallParams = await createCoinCall(coinParams);

// In your component
function CreateCoinComponent() {
  const { data: writeConfig } = useSimulateContract({
    ...contractCallParams,
  });
  
  const { writeContract, status } = useWriteContract(writeConfig);
  
  return (
    <button disabled={!writeContract || status !== 'pending'} onClick={() => writeContract?.()}>
      {status === 'pending' ? 'Creating...' : 'Create Coin'}
    </button>
  );
}
```

## Metadata Validation

The SDK validates the metadata URI content before creating the coin. The `uri` parameter is expected to be a `ValidMetadataURI` type, which means it should point to valid metadata following the structure described in the [Metadata](/coins/contracts/metadata) section.

```typescript
import { validateMetadataURIContent } from "@zoralabs/coins-sdk";

// This will throw an error if the metadata is not valid
await validateMetadataURIContent(uri);
```

## Getting Coin Address from Transaction Receipt

Once the transaction is complete, you can extract the deployed coin address from the transaction receipt logs using the `getCoinCreateFromLogs` function:

```typescript
import { getCoinCreateFromLogs } from "@zoralabs/coins-sdk";

// Assuming you have a transaction receipt
const coinDeployment = getCoinCreateFromLogs(receipt);
console.log("Deployed coin address:", coinDeployment?.coin);
```