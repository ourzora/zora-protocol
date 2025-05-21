import { create1155 } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, creatorAccount } from "./config";

const { parameters, contractAddress } = await create1155({
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
  publicClient,
});

// simulate the transaction
const { request } = await publicClient.simulateContract(parameters);

// execute the transaction
await walletClient.writeContract(request);

export { contractAddress };
