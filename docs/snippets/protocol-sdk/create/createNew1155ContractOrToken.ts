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
  },
  // account to execute the transaction (the creator)
  account: address!,
});

const { writeContract } = useWriteContract();

writeContract(parameters);

export { contractAddress };
