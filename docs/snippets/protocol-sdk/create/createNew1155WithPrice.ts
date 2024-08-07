import {
  useAccount,
  useChainId,
  usePublicClient,
  useWriteContract,
} from "wagmi";
import { parseEther } from "viem";
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
      // setting a price per token on the `salesConfig` will
      // result in the token being created with a fixed price in addition
      // to the mint fee.  In this case, creator rewards will not be earned
      // on the mint fee, the `ZoraCreatorFixedPriceSaleStrategy` is setup
      // as the minter for this token, and correspondingly the onchain
      // secondary market feature will NOT be used for tokens minted using
      // that minter.
      pricePerToken: parseEther("0.1"), // [!code hl]
    },
  },
  // account to execute the transaction (the creator)
  account: address!,
});

const { writeContract } = useWriteContract();

writeContract(parameters);

export { contractAddress };
