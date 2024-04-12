# Zora Protocol SDK

Protocol SDK allows developers to create tokens using the Zora Protocol and mint them.

## Installing

[viem](https://viem.sh/) is a peerDependency of protocol-sdk. If not already installed, it needs to be installed alongside the protocol sdk.

- `npm install viem`
- `npm install `


## Examples

- [Creating a mint from an on-chain contract](#creating-a-mint-from-an-on-chain-contract)
- [Creating an 1155 contract](#creating-an-1155-contract)
- [Premint: create a mint without paying gas](#premint-create-a-mint-without-paying-gas)
- [Updating a premint before it is brought onchain](#updating-a-premint-before-it-is-brought-onchain)
- [Deleting a premint before it is brought onchain](#deleting-a-premint-before-it-is-brought-onchain)
- [Minting a premint and bringing it onchain](#minting-a-premint-and-bringing-it-onchain)

### Creating a mint from an on-chain contract

#### Using viem

```ts
import { createMintClient } from "@zoralabs/protocol-sdk";
import type { Address, PublicClient, WalletClient } from "viem";

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
  const mintClient = createMintClient({ chain: walletClient.chain! });

  // prepare the mint transaction, which can be simulated via an rpc with the public client.
  const prepared = await mintClient.makePrepareMintTokenParams({
    // token to mint
    tokenContract,
    tokenId,
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
  await publicClient.waitForTransactionReceipt({ hash: txHash });
}
```

#### Using wagmi

```tsx
import { createMintClient } from "@zoralabs/protocol-sdk";
import { useEffect, useMemo, useState } from "react";
import { BaseError, SimulateContractParameters, stringify } from "viem";
import {
  Address,
  useAccount,
  useContractWrite,
  useNetwork,
  usePrepareContractWrite,
  usePublicClient,
  useWaitForTransaction,
} from "wagmi";

// custom hook that gets the mintClient for the current chain
const useMintClient = () => {
  const publicClient = usePublicClient();

  const { chain } = useNetwork();

  const mintClient = useMemo(
    () => chain && createMintClient({ chain, publicClient }),
    [chain, publicClient],
  );

  return mintClient;
};

export const Mint = ({
  tokenId,
  tokenContract,
}: {
  tokenId: string;
  tokenContract: Address;
}) => {
  // call custom hook to get the mintClient
  const mintClient = useMintClient();

  // value will be set by the form
  const [quantityToMint, setQuantityToMint] = useState<number>(1);

  // params for the prepare contract write hook
  const [params, setParams] = useState<SimulateContractParameters>();

  const { address } = useAccount();

  useEffect(() => {
    if (!mintClient || !address) return;

    const makeParams = async () => {
      // make the params for the prepare contract write hook
      const params = await mintClient.makePrepareMintTokenParams({
        tokenId,
        tokenContract,
        minterAccount: address,
        mintArguments: {
          mintToAddress: address,
          quantityToMint,
        },
      });
      setParams(params);
    };

    makeParams();
  }, [mintClient, address, quantityToMint]);

  const { config } = usePrepareContractWrite(params);

  const { write, data, error, isLoading, isError } = useContractWrite(config);
  const {
    data: receipt,
    isLoading: isPending,
    isSuccess,
  } = useWaitForTransaction({ hash: data?.hash });

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
        <input
          placeholder="quantity to mint"
          onChange={(e) => setQuantityToMint(Number(e.target.value))}
        />
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

### Creating an 1155 contract

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

### Premint: create a mint without paying gas

```ts
import { createPremintClient } from "@zoralabs/protocol-sdk";
import type { Address, PublicClient, WalletClient } from "viem";

async function createForFree({
  walletClient,
  publicClient,
  creatorAccount,
}: {
  // wallet client that will submit the transaction
  walletClient: WalletClient;
  // public client that will simulate the transaction
  publicClient: PublicClient;
  // address of the token contract
  creatorAccount: Account | Address;
}) {
  const premintClient = createPremintClient({
    chain: walletClient.chain!,
    publicClient,
  });

  // create and sign a free token creation.
  const createdPremint = await premintClient.createPremint({
    walletClient,
    creatorAccount,
    // if true, will validate that the creator is authorized to create premints on the contract.
    checkSignature: true,
    // collection info of collection to create
    collection: {
      contractAdmin: typeof creatorAccount === "string" ? creatorAccount : creatorAccount.address,
      contractName: "Testing Contract",
      contractURI:
        "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
    },
    // token info of token to create
    tokenCreationConfig: {
      tokenURI:
        "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
    },
  });

  const premintUid = createdPremint.uid;
  const premintCollectionAddress = createdPremint.verifyingContract;

  return {
    // unique id of created premint, which can be used later to
    // update or delete the premint
    uid: premintUid,
    tokenContractAddress: premintCollectionAddress,
  };
}
```

### Updating a premint before it is brought onchain

Before a premint is brought onchain, it can be updated by the original creator of that token, by having that creator sign a message indicating the update. This is useful for updating the tokenURI, other metadata, or token sale configuration (price, duration, limits, etc.):

```ts
import { createPremintClient } from "@zoralabs/protocol-sdk";
import type { Address, PublicClient, WalletClient } from "viem";

async function updateCreatedForFreeToken(
  walletClient: WalletClient,
  premintUid: number,
) {
  const premintClient = createPremintClient({ chain: walletClient.chain! });

  // sign a message to update the created for free token, and store the update
  await premintClient.updatePremint({
    collection: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    uid: premintUid,
    // WalletClient doing the signature
    walletClient,
    // Token information, falls back to defaults set in DefaultMintArguments.
    tokenConfigUpdates: {
      tokenURI:
        "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
    },
  });
}
```

### Deleting a premint before it is brought onchain

Before a premint is brought onchain, it can be deleted by the original creator of that token, by having that creator sign a message indicating the deletion:

```ts
async function deleteCreatedForFreeToken(walletClient: WalletClient) {
  const premintClient = createPremintClient({ chain: walletClient.chain! });

  // sign a message to delete the premint, and store the deletion
  await premintClient.deletePremint({
    // Extra step to check the signature on-chain before attempting to sign
    collection: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
    uid: 23,
    // WalletClient doing the signature
    walletClient,
  });
}
```

### Minting a premint and bringing it onchain

```ts
import { createPremintClient } from "@zoralabs/protocol-sdk";
import type { Address, PublicClient, WalletClient } from "viem";

async function mintCreatedForFreeToken(
  walletClient: WalletClient,
  publicClient: PublicClient,
  minterAccount: Address,
) {
  const premintClient = createPremintClient({ chain: walletClient.chain! });

  const simulateContractParameters = await premintClient.makeMintParameters({
    minterAccount,
    tokenContract: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
    uid: 3,
    mintArguments: {
      quantityToMint: 1,
      mintComment: "",
    },
  });

  // simulate the transaction and get any validation errors
  const { request } = await publicClient.simulateContract(
    simulateContractParameters,
  );

  // submit the transaction to the network
  const txHash = await walletClient.writeContract(request);

  // wait for the transaction to be complete
  const receipt = await publicClient.waitForTransactionReceipt({
    hash: txHash,
  });

  const { urls } = await premintClient.getDataFromPremintReceipt(receipt);

  // block explorer url:
  console.log(urls.explorer);
  // collect url:
  console.log(urls.zoraCollect);
  // manage url:
  console.log(urls.zoraManage);
}
```
