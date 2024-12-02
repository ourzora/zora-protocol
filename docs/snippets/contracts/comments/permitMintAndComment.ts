import {
  callerAndCommenterAddress,
  callerAndCommenterABI,
  permitMintAndCommentTypedDataDefinition,
  PermitMintAndComment,
} from "@zoralabs/protocol-deployments";
import { getClient } from "@reservoir0x/relay-sdk";
import {
  zeroAddress,
  keccak256,
  toBytes,
  encodeFunctionData,
  parseEther,
} from "viem";
import { base, zora } from "viem/chains";
import {
  walletClient,
  minterAccount,
  contractAddress1155,
  tokenId1155,
} from "./config";

// 1. Create and sign a cross-chain permit mint and comment.

// Calculate a timestamp 30 seconds from now
const thirtySecondsFromNow =
  BigInt(Math.round(new Date().getTime() / 1000)) + 30n;
// Generate a random nonce
const randomNonce = () => keccak256(toBytes(Math.round(Math.random() * 1000)));

// Define the number of 1155 tokens to mint
const quantityToMint = 3n;

// Define the permit mint and comment object
const permit: PermitMintAndComment = {
  commenter: minterAccount,
  comment: "This is a test comment",
  deadline: thirtySecondsFromNow,
  mintReferral: zeroAddress, // No mint referral in this case
  quantity: quantityToMint,
  collection: contractAddress1155,
  tokenId: tokenId1155,
  nonce: randomNonce(),
  sourceChainId: base.id, // The chain where the transaction originates (Base)
  destinationChainId: zora.id, // The chain where the mint and comment will be executed (Zora)
};

// Generate the typed data for the permit mint and comment using the helper
// method from @zoralabs/protocol-deployments
const typedData = permitMintAndCommentTypedDataDefinition(permit);

// Sign the permit
const signature = await walletClient.signTypedData(typedData);

const mintFee = parseEther("0.000111");

// 2. Execute the cross-chain transaction with relay

// Initialize the relay client
const relayClient = getClient();

// Value to send to the CallerAndCommenter contract on the destination chain
// is the mint fee multiplied by the quantity of tokens to mint
const valueToSend = mintFee * quantityToMint;

// Get a quote from relay for the cross-chain transaction
const quote = await relayClient.actions.getQuote({
  wallet: walletClient,
  chainId: permit.sourceChainId, // The origin chain (Base)
  toChainId: permit.destinationChainId, // The destination chain (Zora)
  amount: valueToSend.toString(), // The total value to send to the CallerAndCommenter contract on the destination chain
  tradeType: "EXACT_OUTPUT",
  currency: zeroAddress, // ETH
  toCurrency: zeroAddress, // ETH
  txs: [
    {
      to: callerAndCommenterAddress[
        permit.destinationChainId as keyof typeof callerAndCommenterAddress
      ],
      value: valueToSend.toString(),
      // We will call permitTimedSaleMintAndComment on the destination chain
      data: encodeFunctionData({
        abi: callerAndCommenterABI,
        functionName: "permitTimedSaleMintAndComment",
        args: [permit, signature],
      }),
    },
  ],
});

// Execute the cross-chain transaction
await relayClient.actions.execute({
  quote,
  wallet: walletClient, // The wallet initiating the transaction
});
