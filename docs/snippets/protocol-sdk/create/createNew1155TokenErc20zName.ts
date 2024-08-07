import { createCreatorClient } from "@zoralabs/protocol-sdk";
import { publicClient, chainId, creatorAccount } from "./config";

const creatorClient = createCreatorClient({ chainId, publicClient });

const { parameters } = await creatorClient.create1155({
  contract: {
    name: "testContract",
    uri: "ipfs://DUMMY/contract.json",
  },
  token: {
    tokenMetadataURI: "ipfs://DUMMY/token.json",
    salesConfig: {
      // manually specifying the erc20 name and symbol
      erc20Name: "My Token Name", // [!code hl]
      erc20Symbol: "MTN", // [!code hl]
    },
  },
  account: creatorAccount,
});

// simulate the transaction
await publicClient.simulateContract(parameters);
