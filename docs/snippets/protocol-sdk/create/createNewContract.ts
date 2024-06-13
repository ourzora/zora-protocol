import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, chainId, creatorAccount } from "./config";

const creatorClient = createCreatorClient({ chainId, publicClient });

const { parameters, collectionAddress } = await creatorClient.create1155({
  // by providing a contract creation config, the contract will be created
  // if it does not exist at a deterministic address
  contract: {
    // contract name
    name: "testContract",
    // contract metadata uri
    uri: "ipfs://DUMMY/contract.json",
  },
  token: {
    tokenMetadataURI: "ipfs://DUMMY/token.json",
  },
  // account to execute the transaction (the creator)
  account: creatorAccount,
  // how many tokens to mint to the creator upon token creation
});

// simulate the transaction
const { request } = await publicClient.simulateContract(parameters);

// execute the transaction
await walletClient.writeContract(request);

export { collectionAddress };
