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
} from "./config";
import { commentIdentifier } from "./comment";
import { zeroAddress, parseEther } from "viem";

const sparkValue = parseEther("0.000001");

// this identifies the comment that we are replying to
// it can be gotten from the `Commented` event when commenting,
// or from the subgraph when querying for comments
const replyTo: CommentIdentifier = {
  commenter: commentIdentifier.commenter, // [!code hl]
  contractAddress: commentIdentifier.contractAddress, // [!code hl]
  tokenId: commentIdentifier.tokenId, // [!code hl]
  nonce: commentIdentifier.nonce, // [!code hl]
};

const referrer = zeroAddress;

const smartWallet = zeroAddress;

const hash = await walletClient.writeContract({
  abi: commentsABI,
  address: commentsAddress[chainId],
  functionName: "comment",
  args: [
    commenterAccount,
    contractAddress1155,
    tokenId1155,
    "This is a test reply",
    // when replying to a comment, we must pass the comment identifier of the comment we are replying to
    replyTo, // [!code hl]
    smartWallet,
    referrer,
  ],
  account: commenterAccount,
  value: sparkValue,
});

const receipt = await publicClient.waitForTransactionReceipt({ hash });
if (receipt.status !== "success") {
  throw new Error("Transaction failed");
}
