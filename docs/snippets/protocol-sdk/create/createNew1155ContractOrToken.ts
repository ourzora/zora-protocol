import { create1155CreatorClient } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient } from "./config";

const creatorClient = create1155CreatorClient({ publicClient });

const { request } = await creatorClient.createNew1155Token({
  // by providing a contract creation config, the contract will be created
  // if it does not exist at a deterministic address
  contract: {
    // contract name
    name: "testContract",
    // contract metadata uri
    uri: "ipfs://DUMMY/contract.json",
  },
  // token metadata uri
  tokenMetadataURI: "ipfs://DUMMY/token.json",
  // accoun to execute the transaction (the creator)
  account: "0x1234567890123456789012345678901234567890",
  // how many tokens to mint to the creator upon token creation
  mintToCreatorCount: 1,
});

// simulate the transaction
const { request: simulateRequest } =
  await publicClient.simulateContract(request);

// execute the transaction
const hash = await walletClient.writeContract(simulateRequest);
// wait for the response
const receipt = await publicClient.waitForTransactionReceipt({ hash });

if (receipt.status !== "success") {
  throw new Error("Transaction failed");
}
