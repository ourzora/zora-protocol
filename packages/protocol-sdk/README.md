# Zora Protocol SDK

Protocol SDK allows users to create tokens using the Zora Protocol, and mint them.

## Installing

[viem](https://viem.sh/) is a peerDependency of protocol-sdk. If not already installed, it needs to be installed alongside the protocol sdk.

- `npm install viem`
- `npm install `

### Creating a mint from an on-chain contract:

#### Using viem

```ts
import {createMintClient} from "@zoralabs/protocol-sdk";
import type {Address, PublicClient, WalletClient} from "viem";

async function mintNFT({
  walletClient,
  publicClient,
  tokenContract,
  tokenId,
  mintToAddress,
  quantityToMint,
  mintReferral,
}: {
  // wallet client that will submit the transaction
  walletClient: WalletClient;
  // public client that will simulate the transaction
  publicClient: PublicClient;
  // address of the token contract
  tokenContract: Address;
  // id of the token to mint
  tokenId: bigint;
  // address that will receive the minted token
  mintToAddress: Address;
  // quantity of tokens to mint
  quantityToMint: number;
  // optional address that will receive a mint referral reward
  mintReferral?: Address;
}) {
  const mintClient = createMintClient({chain: walletClient.chain!});

  // get mintable information about the token.
  const mintable = await mintClient.getMintable({
    tokenContract,
    tokenId,
  });

  // prepare the mint transaction, which can be simulated via an rpc with the public client.
  const prepared = await mintClient.makePrepareMintTokenParams({
    // token to mint
    mintable,
    mintArguments: {
      // address that will receive the token
      mintToAddress,
      // quantity of tokens to mint
      quantityToMint,
      // comment to include with the mint
      mintComment: "My comment",
      // optional address that will receive a mint referral reward
      mintReferral,
    },
    // account that is to invoke the mint transaction
    minterAccount: walletClient.account!.address,
  });

  // simulate the transaction and get any validation errors
  const { request } = await publicClient.simulateContract(prepared);

  // submit the transaction to the network
  const txHash = await walletClient.writeContract(request);

  // wait for the transaction to be complete
  await publicClient.waitForTransactionReceipt({hash: txHash});
}
```

#### Using wagmi

```tsx
import {createMintClient, Mintable} from "@zoralabs/protocol-sdk";
import {useEffect, useMemo, useState} from "react";
import {BaseError, SimulateContractParameters, stringify} from "viem";
import {Address, useAccount, useContractWrite, useNetwork, usePrepareContractWrite, usePublicClient, useWaitForTransaction} from "wagmi";

// custom hook that gets the mintClient for the current chain
const useMintClient = () => {
  const publicClient = usePublicClient();

  const {chain} = useNetwork();

  const mintClient = useMemo(() => chain && createMintClient({chain, publicClient}), [chain, publicClient]);

  return mintClient;
};

export const Mint = ({tokenId, tokenContract}: {tokenId: string; tokenContract: Address}) => {
  // call custom hook to get the mintClient
  const mintClient = useMintClient();

  // value will be set by the form
  const [quantityToMint, setQuantityToMint] = useState<number>(1);

  // fetched mintable info from the sdk
  const [mintable, setMintable] = useState<Mintable>();

  useEffect(() => {
    // fetch the mintable token info
    const fetchMintable = async () => {
      if (mintClient) {
        const mintable = await mintClient.getMintable({tokenId, tokenContract});
        setMintable(mintable);
      }
    };

    fetchMintable();
  }, [mintClient, tokenId, tokenContract]);

  // params for the prepare contract write hook
  const [params, setParams] = useState<SimulateContractParameters>();

  const {address} = useAccount();

  useEffect(() => {
    if (!mintable || !mintClient || !address) return;

    const makeParams = async () => {
      // make the params for the prepare contract write hook
      const params = await mintClient.makePrepareMintTokenParams({
        mintable,
        minterAccount: address,
        mintArguments: {
          mintToAddress: address,
          quantityToMint,
        },
      });
      setParams(params);
    };

    makeParams();
  }, [mintable, mintClient, address, quantityToMint]);

  const {config} = usePrepareContractWrite(params);

  const {write, data, error, isLoading, isError} = useContractWrite(config);
  const {data: receipt, isLoading: isPending, isSuccess} = useWaitForTransaction({hash: data?.hash});

  return (
    <>
      <h3>Mint a token</h3>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          write?.();
        }}
      >
        {/* input for quantity to mint: */}
        <input placeholder="quantity to mint" onChange={(e) => setQuantityToMint(Number(e.target.value))} />
        <button disabled={!write} type="submit">
          Mint
        </button>
      </form>

      {isLoading && <div>Check wallet...</div>}
      {isPending && <div>Transaction pending...</div>}
      {isSuccess && (
        <>
          <div>Transaction Hash: {data?.hash}</div>
          <div>
            Transaction Receipt: <pre>{stringify(receipt, null, 2)}</pre>
          </div>
        </>
      )}
      {isError && <div>{(error as BaseError)?.shortMessage}</div>}
    </>
  );
};
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
