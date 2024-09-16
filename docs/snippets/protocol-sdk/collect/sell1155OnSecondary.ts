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

// Prepare the sell transaction
const { parameters, price, error } = await collectorClient.sell1155OnSecondary({
  // 1155 contract address
  contract: "0xCD860870DE521cDb0C5ae89E80bBa057Cd30Bf8C",
  // 1155 token id to sell
  tokenId: 1n,
  // quantity of tokens to sell
  quantity: 3n,
  // account that will execute the sell transaction
  account: address!,
  // Slippage tolerance, ensuring that a minimum amount of ETH is received
  // for the given quantity of 1155 tokens to sell.
  slippage: 0.0005,
});

if (error) {
  throw new Error(error);
}

console.log("Price per token (wei):", price!.wei.perToken);
console.log("Total price (wei):", price!.wei.total);

const { writeContract } = useWriteContract();

// Write the sell transaction to the network
writeContract(parameters);
