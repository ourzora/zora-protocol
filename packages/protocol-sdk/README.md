# Premint SDK

Protocol SDK allows users to manage zora mints and collects.

## Installing

[viem](https://viem.sh/) is a peerDependency of protocol-sdk. If not already installed, it needs to be installed alongside the protocol sdk.

- `npm install viem`
- `npm install `

### Creating a mint from an on-chain contract:

```ts
import { createMintClient } from "@zoralabs/protocol-sdk";
import type { Address, WalletClient } from "viem";

async function mintNFT(
  walletClient: WalletClient,
  address: Address,
  tokenId: bigint,
) {
  const mintAPI = createMintClient({ chain: walletClient.chain });
  await mintAPI.mintNFT({
    walletClient,
    address,
    tokenId,
    mintArguments: {
      quantityToMint: 23,
      mintComment: "Helo",
    },
  });
}
```

### Creating an 1155 contract:

If an object with {name, uri} is passed in to this helper, it uses the creatorAccount and those values to either 1) create or 2) mint to that existing contract.

If you wish to mint on an existing contract, pass that contract in the contract field. The return value is the prepared transaction that you can use viem or wagmi to send.

```ts
import type { PublicClient } from "viem";
import { create1155CreatorClient } from "@zoralabs/protocol-sdk";

export async function createContract({
  publicClient,
  walletClient,
}: {
  publicClient: PublicClient;
  walletClient: WalletClient;
}) {
  const creatorClient = create1155CreatorClient({ publicClient });
  const { request } = await creatorClient.createNew1155Token({
    contract: {
      name: "testContract",
      uri: demoContractMetadataURI,
    },
    tokenMetadataURI: demoTokenMetadataURI,
    account: creatorAccount,
    mintToCreatorCount: 1,
  });
  const { request: simulateRequest } = publicClient.simulateContract(request);
  const hash = await walletClient.writeContract(simulateRequest);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return receipt;
}
```

### Creating a premint:

```ts
import { PremintAPI } from "@zoralabs/protocol-sdk";
import type { Address, WalletClient } from "viem";

async function makePremint(walletClient: WalletClient) {
  // Create premint
  const premint = await createPremintAPI(walletClient.chain).createPremint({
    // Extra step to check the signature on-chain before attempting to sign
    checkSignature: true,
    // Collection information that this premint NFT will exist in once minted.
    collection: {
      contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
      contractName: "Testing Contract",
      contractURI:
        "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
    },
    // WalletClient doing the signature
    walletClient,
    // Token information, falls back to defaults set in DefaultMintArguments.
    token: {
      tokenURI:
        "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
    },
  });

  console.log(`created ZORA premint, link: ${premint.url}`);
  return premint;
}
```

### Updating a premint:

```ts
import { PremintAPI } from "@zoralabs/premint-sdk";
import type { Address, WalletClient } from "viem";

async function updatePremint(walletClient: WalletClient) {
  // Create premint API object passing in the current wallet chain (only zora and zora testnet are supported currently).
  const premintAPI = createPremintAPI(walletClient.chain);

  // Create premint
  const premint = await premintAPI.updatePremint({
    // Extra step to check the signature on-chain before attempting to sign
    collection: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    uid: 23,
    // WalletClient doing the signature
    walletClient,
    // Token information, falls back to defaults set in DefaultMintArguments.
    token: {
      tokenURI:
        "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
    },
  });

  console.log(`updated ZORA premint, link: ${premint.url}`);
  return premint;
}
```

### Deleting a premint:

```ts
import { PremintAPI } from "@zoralabs/premint-sdk";
import type { Address, WalletClient } from "viem";

async function deletePremint(walletClient: WalletClient) {
  // Create premint API object passing in the current wallet chain (only zora and zora testnet are supported currently).
  const premintAPI = createPremintClient({ chain: walletClient.chain });

  // Create premint
  const premint = await premintAPI.deletePremint({
    // Extra step to check the signature on-chain before attempting to sign
    collection: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    uid: 23,
    // WalletClient doing the signature
    walletClient,
  });

  console.log(`updated ZORA premint, link: ${premint.url}`);
  return premint;
}
```

### Executing a premint:

```ts
import { PremintAPI } from "@zoralabs/premint-sdk";
import type { Address, WalletClient } from "viem";

async function executePremint(
  walletClient: WalletClient,
  premintAddress: Address,
  premintUID: number,
) {
  const premintAPI = createPremintClient({ chain: walletClient.chain });

  return await premintAPI.executePremintWithWallet({
    data: premintAPI.getPremintData(premintAddress, premintUID),
    walletClient,
    mintArguments: {
      quantityToMint: 1,
    },
  });
}
```

### Deleting a premint:

```ts
import {PremintAPI} from '@zoralabs/premint-sdk';
import type {Address, WalletClient} from 'viem';

async function deletePremint(walletClient: WalletClient, collection: Address, uid: number) {
    const premintAPI = createPremintClient({chain: walletClient.chain});

    return await premintAPI.deletePremint({
        walletClient,
        uid,
        collection
    });
}

```
