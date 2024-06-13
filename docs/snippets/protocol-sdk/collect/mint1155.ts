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

// prepare the mint transaction
const { parameters } = await collectorClient.mint({
  // 1155 contract address
  tokenContract: "0xCD860870DE521cDb0C5ae89E80bBa057Cd30Bf8C",
  // type of item to mint
  mintType: "1155", // [!code hl]
  // 1155 token id to mint
  tokenId: 1n, // [!code hl]
  // quantity of tokens to mint
  quantityToMint: 3,
  // optional comment to include with the mint
  mintComment: "My comment",
  // optional address that will receive a mint referral reward
  mintReferral: "0x0C8596Ee50e06Ce710237c9c905D4aB63A132207",
  // account that is to invoke the mint transaction
  minterAccount: address!,
});

const { writeContract } = useWriteContract();

// write the mint transaction to the network
writeContract(parameters);
