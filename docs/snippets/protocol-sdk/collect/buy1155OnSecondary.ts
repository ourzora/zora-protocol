import {
  useAccount,
  useChainId,
  usePublicClient,
  useWriteContract,
} from "wagmi";
import { createCollectorClient } from "@zoralabs/protocol-sdk";

const chainId = useChainId();
const publicClient = usePublicClient()!;
const { address } = useAccount();

const collectorClient = createCollectorClient({ chainId, publicClient });

// Prepare the buy transaction
const { parameters, price, error } = await collectorClient.buy1155OnSecondary({
  // 1155 contract address
  contract: "0xCD860870DE521cDb0C5ae89E80bBa057Cd30Bf8C",
  // 1155 token id to buy
  tokenId: 1n,
  // quantity of tokens to buy
  quantity: 3n,
  // account that will execute the buy transaction
  account: address!,
  // (optional) comment to add to the swap
  comment: "test comment",
});

if (error) {
  throw new Error(error);
}

console.log("Price per token (wei):", price!.wei.perToken);
console.log("Total price (wei):", price!.wei.total);

const { writeContract } = useWriteContract();

// Write the buy transaction to the network
writeContract(parameters);
