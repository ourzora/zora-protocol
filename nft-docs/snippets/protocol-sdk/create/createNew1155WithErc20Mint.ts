import { create1155 } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, creatorAccount } from "./config";
import { contract } from "./data";

const erc20TokenAddress = "0xa6b280b42cb0b7c4a4f789ec6ccc3a7609a1bc39";

const { parameters, contractAddress } = await create1155({
  contract,
  token: {
    tokenMetadataURI: "ipfs://DUMMY/token.json",
    salesConfig: {
      // to have the token priced in erc20, the type must be set to "erc20Mint"
      type: "erc20Mint", // [!code hl]
      // `currency` field must be set if it is an erc20 mint
      currency: erc20TokenAddress, // [!code hl]
      // the price per token in the erc20 token value
      pricePerToken: 1000000000000000000n, // [!code hl]
    },
  },
  account: creatorAccount,
  publicClient,
});

// simulate the transaction
const { request } = await publicClient.simulateContract(parameters);

// execute the transaction
await walletClient.writeContract(request);

export { contractAddress };
