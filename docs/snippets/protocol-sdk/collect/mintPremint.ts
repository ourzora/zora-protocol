import { createCollectorClient } from "@zoralabs/protocol-sdk";
import { walletClient, publicClient, chain } from "./config";
import { collection, uid } from "./createPremint";

// initialize the collect sdk with the chain configuration
const collectorClient = createCollectorClient({ chain });

// get parameters to mint a premint, which can be used to simulate and submit the transaction
const simulateContractParameters = await collectorClient.mint({
  // the deterministic premint collection address
  tokenContract: collection,
  // type of item to mint
  mintType: "premint", // [!code hl]
  // the uid of the premint to mint
  uid, // [!code hl]
  // how many tokens to mint
  quantityToMint: 3,
  // Comment to attach to the mint
  mintComment: "Mint comment",
  // the account to execute the transaction
  minterAccount: "0xf69fEc6d858c77e969509843852178bd24CAd2B6",
});

// simulate the transaction and get any validation errors
const { request } = await publicClient.simulateContract(
  simulateContractParameters,
);

// submit the transaction to the network
await walletClient.writeContract(request);
