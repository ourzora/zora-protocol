import {
  createCollectorClient,
  createCreatorClient,
  getPremintCollectionAddress,
} from "src";
import {
  LocalAccount,
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { zoraSepolia } from "viem/chains";

const publicClient = createPublicClient({
  chain: zoraSepolia,
  transport: http(),
});

const walletClient = createWalletClient({
  chain: zoraSepolia,
  transport: http(),
});

const creatorClient = createCreatorClient({
  chainId: zoraSepolia.id,
  publicClient,
});

const collectorClient = createCollectorClient({
  chainId: zoraSepolia.id,
  publicClient,
});

export const createPremintsOnContract = async ({
  creatorAccount,
}: {
  creatorAccount: LocalAccount;
}) => {
  const collectionAddress = await getPremintCollectionAddress({
    publicClient,
    contract: {
      contractAdmin: creatorAccount.address,
      contractName: "testContract",
      contractURI:
        "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
    },
  });

  console.log({ collectionAddress });

  const { typedDataDefinition, submit } = await creatorClient.createPremint({
    contract: {
      contractAdmin: creatorAccount.address,
      contractName: "testContract",
      contractURI:
        "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
    },
    token: {
      payoutRecipient: creatorAccount.address,
      tokenURI:
        "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
      pricePerToken: parseEther("0.001"),
    },
  });

  const signature = await walletClient.signTypedData({
    account: creatorAccount,
    ...typedDataDefinition,
  });

  await submit({
    signature,
  });

  const mints = await collectorClient.getTokensOfContract({
    tokenContract: collectionAddress,
  });

  console.log({ mints: mints.map((x) => x.mintable) });
};

const setupTestContracts = async () => {
  const creatorAccount = privateKeyToAccount(
    // random private key created by cast
    "0x0d32fcabfe28c779974a77dc635163f062be2bc0b10eea62994235617b44092f",
  );

  // create 2 premints on a contract
  await createPremintsOnContract({
    creatorAccount,
  });
};

setupTestContracts();
