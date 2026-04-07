import {
  commentsABI,
  commentsAddress,
  CommentIdentifier,
} from "@zoralabs/protocol-deployments";
import {
  commenterAccount,
  contractAddress1155,
  publicClient,
  tokenId1155,
  walletClient,
  chainId,
  sparkerAccount,
} from "./config";
import { keccak256, toBytes, zeroAddress, parseEther } from "viem";

// quantity of sparks to spark (like) the comment with
const sparksQuantity = 1n;

const sparkValue = parseEther("0.000001");

const commentIdentifier: CommentIdentifier = {
  commenter: commenterAccount,
  contractAddress: contractAddress1155,
  tokenId: tokenId1155,
  nonce: keccak256(toBytes(1)),
};

const referrer = zeroAddress;

const hash = await walletClient.writeContract({
  abi: commentsABI,
  address: commentsAddress[chainId],
  functionName: "sparkComment",
  args: [commentIdentifier, sparksQuantity, referrer],
  account: sparkerAccount,
  value: sparksQuantity * sparkValue,
});

const receipt = await publicClient.waitForTransactionReceipt({ hash });
if (receipt.status !== "success") {
  throw new Error("Transaction failed");
}
