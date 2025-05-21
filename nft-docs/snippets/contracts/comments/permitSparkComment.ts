import {
  commentsABI,
  commentsAddress,
  PermitSparkComment,
  sparkValue,
  permitSparkCommentTypedDataDefinition,
} from "@zoralabs/protocol-deployments";
import { getClient } from "@reservoir0x/relay-sdk";
import { zeroAddress, keccak256, toBytes, encodeFunctionData } from "viem";
import { base, zora } from "viem/chains";
import { walletClient, chainId, sparkerAccount } from "./config";
import { commentIdentifier } from "./comment";

// 1. Create and sign a cross-chain permit spark comment.

// Calculate a timestamp 30 seconds from now
const thirtySecondsFromNow =
  BigInt(Math.round(new Date().getTime() / 1000)) + 30n;
// Generate a random nonce
const randomNonce = () => keccak256(toBytes(Math.round(Math.random() * 1000)));

// Get the comments contract address for the current chain
const commentsContractAddress = commentsAddress[chainId];

// Define the number of sparks to add
const sparksQuantity = 3n;

// Define the permit spark comment object
const permitSparkComment: PermitSparkComment = {
  comment: commentIdentifier, // The comment to spark
  deadline: thirtySecondsFromNow,
  nonce: randomNonce(),
  sparker: sparkerAccount, // The account sparking the comment
  sparksQuantity: sparksQuantity, // The number of sparks to add
  sourceChainId: base.id, // The chain where the transaction originates (Base)
  destinationChainId: zora.id, // The chain where the spark will be stored (Zora)
  referrer: zeroAddress, // No referrer in this case
};

// Generate the typed data for the permit spark comment using the helper
// method from @zoralabs/protocol-deployments
const permitSparkCommentTypedData =
  permitSparkCommentTypedDataDefinition(permitSparkComment);

// Sign the permit
const permitSparkCommentSignature = await walletClient.signTypedData(
  permitSparkCommentTypedData,
);

// 2. Execute the cross-chain transaction with relay

// Initialize the relay client
const relayClient = getClient();

// Get a quote from relay for the cross-chain transaction
const quote = await relayClient.actions.getQuote({
  wallet: walletClient,
  chainId: permitSparkComment.sourceChainId, // The origin chain (Base)
  toChainId: permitSparkComment.destinationChainId, // The destination chain (Zora)
  amount: (sparkValue() * sparksQuantity).toString(), // The total value to send to the comments contract on the destination chain
  tradeType: "EXACT_OUTPUT",
  currency: zeroAddress, // ETH
  toCurrency: zeroAddress, // ETH
  txs: [
    {
      to: commentsContractAddress,
      value: sparkValue().toString(),
      // We will call permitSparkComment on the destination chain
      data: encodeFunctionData({
        abi: commentsABI,
        functionName: "permitSparkComment",
        args: [permitSparkComment, permitSparkCommentSignature],
      }),
    },
  ],
});

// Execute the cross-chain transaction
await relayClient.actions.execute({
  quote,
  wallet: walletClient, // The wallet initiating the transaction
});
