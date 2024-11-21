import {
  commentsABI,
  commentsAddress,
  emptyCommentIdentifier,
  permitCommentTypedDataDefinition,
  PermitComment,
  sparkValue,
} from "@zoralabs/protocol-deployments";
import { getClient } from "@reservoir0x/relay-sdk";
import { zeroAddress, keccak256, toBytes, encodeFunctionData } from "viem";
import { base, zora } from "viem/chains";
import {
  walletClient,
  chainId,
  commenterAccount,
  contractAddress1155,
  tokenId1155,
} from "./config";

// 1. Create and sign a cross-chain permit comment.

// Calculate a timestamp 30 seconds from now
const thirtySecondsFromNow =
  BigInt(Math.round(new Date().getTime() / 1000)) + 30n;
// Generate a random nonce
const randomNonce = () => keccak256(toBytes(Math.round(Math.random() * 1000)));

// Get the comments contract address for the current chain
const commentsContractAddress = commentsAddress[chainId];

// Define the permit comment object
const permitComment: PermitComment = {
  sourceChainId: base.id, // The chain where the transaction originates (Base)
  destinationChainId: zora.id, // The chain where the comment will be stored (Zora)
  contractAddress: contractAddress1155, // The address of the 1155 contract
  tokenId: tokenId1155, // The 1155 token ID being commented on
  commenter: commenterAccount, // The account making the comment.
  text: "hello world", // The content of the comment
  deadline: thirtySecondsFromNow,
  nonce: randomNonce(),
  referrer: zeroAddress, // No referrer in this case
  commenterSmartWallet: zeroAddress, // Not using a smart wallet for commenting
  replyTo: emptyCommentIdentifier(), // This is not a reply to another comment
};

// Generate the typed data for the permit comment using the helper
// method from @zoralabs/protocol-deployments
const permitCommentTypedData = permitCommentTypedDataDefinition(permitComment);

// Sign the permit
const permitCommentSignature = await walletClient.signTypedData(
  permitCommentTypedData,
);

// 2. Execute the cross-chain transaction with relay

// Initialize the relay client
const relayClient = getClient();

// Get a quote from relay for the cross-chain transaction
const quote = await relayClient.actions.getQuote({
  wallet: walletClient,
  chainId: permitComment.sourceChainId, // The origin chain (Base)
  toChainId: permitComment.destinationChainId, // The destination chain (Zora)
  amount: sparkValue().toString(), // The value to send to the comments contract on the destination chain
  tradeType: "EXACT_OUTPUT",
  currency: zeroAddress, // ETH
  toCurrency: zeroAddress, // ETH
  txs: [
    {
      to: commentsContractAddress,
      value: sparkValue().toString(),
      // we will call permitComment on the destination chain
      data: encodeFunctionData({
        abi: commentsABI,
        functionName: "permitComment",
        args: [permitComment, permitCommentSignature],
      }),
    },
  ],
});

// Execute the cross-chain transaction
await relayClient.actions.execute({
  quote,
  wallet: walletClient, // The wallet initiating the transaction
});
