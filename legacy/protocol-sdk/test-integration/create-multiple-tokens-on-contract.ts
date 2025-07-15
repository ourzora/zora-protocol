import { createCreatorClient } from "src";
import {
  Address,
  Chain,
  LocalAccount,
  createPublicClient,
  createWalletClient,
  http,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { zoraSepolia } from "viem/chains";

const publicClient = createPublicClient({
  chain: zoraSepolia as Chain,
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

export const createMultipleTokensOnContract = async ({
  creatorAccount,
}: {
  creatorAccount: LocalAccount;
}) => {
  console.log({ address: creatorAccount.address });
  const { contractAddress, parameters } = await creatorClient.create1155({
    account: creatorAccount.address,
    contract: {
      name: "testContractD",
      uri: "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
    },
    token: {
      tokenMetadataURI:
        "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
    },
  });
  console.log("creating contract and token");

  const { request: requestA } = await publicClient.simulateContract(parameters);

  const hashA = await walletClient.writeContract({
    ...requestA,
    account: creatorAccount,
  });

  const receiptA = await publicClient.waitForTransactionReceipt({
    hash: hashA,
  });

  if (receiptA.status !== "success") {
    throw new Error("create new contract failed");
  }

  console.log("creating new token on contract");

  const { parameters: parametersB } =
    await creatorClient.create1155OnExistingContract({
      account: creatorAccount.address,
      contractAddress,
      token: {
        tokenMetadataURI:
          "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
      },
    });

  const { request: requestB } =
    await publicClient.simulateContract(parametersB);

  const hashB = await walletClient.writeContract({
    ...requestB,
    account: creatorAccount,
  });

  const receiptB = await publicClient.waitForTransactionReceipt({
    hash: hashB,
  });

  if (receiptB.status !== "success") {
    throw new Error("create token on contract failed");
  }

  console.log("created multiple tokens on contract");
};

const setupTestContracts = async () => {
  const creatorAccount = privateKeyToAccount(
    process.env.VITE_PRIVATE_KEY! as Address,
  );

  // create 2 premints on a contract
  await createMultipleTokensOnContract({
    creatorAccount,
  });
};

setupTestContracts();
