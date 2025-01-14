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
    salesConfig: {
      // Name of the erc20z token to create for the secondary sale.  If not provided, uses the contract name
      erc20Name: "testToken",
      // Symbol of the erc20z token to create for the secondary sale.  If not provided, extracts it from the name.
      erc20Symbol: "TEST",
      // Earliest time a token can be minted.  If undefined or 0, then it can be minted immediately.  Defaults to 0n.
      saleStart: 0n,
      // Market countdown, in seconds, that will start once the minimum mints for countdown is reached. Defaults to 24 hours.
      marketCountdown: BigInt(24 * 60 * 60),
      // Minimum quantity of mints that will trigger the countdown.  Defaults to 1111n
      minimumMintsForCountdown: 1111n,
    },
  },
  // account to execute the transaction (the creator)
  account: address!,
  publicClient,
});

const { writeContract } = useWriteContract();

writeContract(parameters);

export { contractAddress };
