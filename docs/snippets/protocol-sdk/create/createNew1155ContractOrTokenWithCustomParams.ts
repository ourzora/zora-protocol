import {
  useAccount,
  useChainId,
  usePublicClient,
  useWriteContract,
} from "wagmi";
import { createCreatorClient } from "@zoralabs/protocol-sdk";

// use wagmi hooks to get the chainId, publicClient, and account
const chainId = useChainId();
const publicClient = usePublicClient()!;
const { address } = useAccount();

const creatorClient = createCreatorClient({ chainId, publicClient });

const { parameters, contractAddress } = await creatorClient.create1155({
  // the contract will be created at a deterministic address
  contract: {
    // contract name
    name: "testContract",
    // contract metadata uri
    uri: "ipfs://DUMMY/contract.json",
  },
  token: {
    tokenMetadataURI: "ipfs://DUMMY/token.json",
    salesConfig: {
      type: "timed",
      erc20Name: "testToken", // If not provided, uses the contract name
      erc20Symbol: "TEST", // If not provided, extracts it from the name.
      saleStart: 0n, // If not provided, sets to 0
      marketCountdown: BigInt(24 * 60 * 60), // If not provided, sets to 24 hours
      minimumMarketEth: 2220000000000000n, // If not provided, sets to 200 mints worth of ETH
    },
  },
  // account to execute the transaction (the creator)
  account: address!,
});

const { writeContract } = useWriteContract();

writeContract(parameters);

export { contractAddress };
