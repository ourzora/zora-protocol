import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, chainId, creatorAccount } from "./config";
import { collectionAddress } from "./createNewContract";

const creatorClient = createCreatorClient({ chainId, publicClient });

const { parameters } = await creatorClient.create1155({
  // by providing a contract address, the token will be created on an existing contract
  // at that address
  contract: collectionAddress, // [!code hl]
  token: {
    // token metadata uri
    tokenMetadataURI: "ipfs://DUMMY/token.json",
  },
  // account to execute the transaction (the creator)
  account: creatorAccount,
});

// simulate the transaction
const { request } = await publicClient.simulateContract(parameters);

// execute the transaction
const hash = await walletClient.writeContract(request);
// wait for the response
await publicClient.waitForTransactionReceipt({ hash });
