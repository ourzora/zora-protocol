import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { create1155 } from "@zoralabs/protocol-sdk";
import { parseEther } from "viem";

// use wagmi hooks to get the chainId, publicClient, and account
const { address } = useAccount();

const publicClient = usePublicClient()!;

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
  publicClient,
});

const { writeContract } = useWriteContract();

writeContract(parameters);

export { contractAddress };
