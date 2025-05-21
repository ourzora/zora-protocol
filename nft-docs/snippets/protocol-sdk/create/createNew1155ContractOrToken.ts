import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { create1155 } from "@zoralabs/protocol-sdk";

// use wagmi hooks to get the chainId, publicClient, and account
const publicClient = usePublicClient()!;
const { address } = useAccount();

const { parameters, contractAddress } = await create1155({
  // the contract will be created at a deterministic address
  contract: {
    // contract name
    name: "testContract",
    // contract metadata uri
    uri: "ipfs://DUMMY/contract.json",
  },
  token: {
    tokenMetadataURI: "ipfs://DUMMY/token.json",
  },
  // account to execute the transaction (the creator)
  account: address!,
  publicClient,
});

const { writeContract } = useWriteContract();

writeContract(parameters);

export { contractAddress };
