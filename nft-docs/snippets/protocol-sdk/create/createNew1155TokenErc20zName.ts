import { create1155 } from "@zoralabs/protocol-sdk";
import { publicClient, creatorAccount } from "./config";

const { parameters } = await create1155({
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
  publicClient,
});

// simulate the transaction
await publicClient.simulateContract(parameters);
