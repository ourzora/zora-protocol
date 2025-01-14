import { createNew1155Token } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, creatorAccount } from "./config";
import { contractAddress } from "./createNewContract";

const { parameters } = await createNew1155Token({
  contractAddress,
  token: {
    tokenMetadataURI: "ipfs://DUMMY/token.json",
  },
  account: creatorAccount,
  chainId: publicClient.chain.id,
});

// simulate the transaction
const { request } = await publicClient.simulateContract(parameters);

// execute the transaction
const hash = await walletClient.writeContract(request);
// wait for the response
await publicClient.waitForTransactionReceipt({ hash });
