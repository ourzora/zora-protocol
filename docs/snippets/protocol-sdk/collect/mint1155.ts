import { createCollectorClient } from "@zoralabs/protocol-sdk";
import { publicClient, walletClient, chain, minterAccount } from "./config";
import { tokenAddress, tokenId } from "./data";

const collectorClient = createCollectorClient({ chain });

// prepare the mint transaction, which can be simulated via an rpc with the public client.
const prepared = await collectorClient.mint({
  // 1155 contract address
  tokenContract: tokenAddress,
  // type of item to mint
  mintType: "1155", // [!code hl]
  // 1155 token id to mint
  tokenId, // [!code hl]
  // quantity of tokens to mint
  quantityToMint: 3,
  // optional comment to include with the mint
  mintComment: "My comment",
  // optional address that will receive a mint referral reward
  mintReferral: "0x0C8596Ee50e06Ce710237c9c905D4aB63A132207",
  // account that is to invoke the mint transaction
  minterAccount: minterAccount,
});

// simulate the transaction
const { request } = await publicClient.simulateContract(prepared);

// execute the transaction
await walletClient.writeContract(request);
