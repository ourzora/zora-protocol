import {
  commentsABI,
  commentsAddress,
  emptyCommentIdentifier,
} from "@zoralabs/protocol-deployments";
import { zeroAddress, parseEther, parseEventLogs } from "viem";
import {
  publicClient,
  walletClient,
  chainId,
  commenterAccount,
  contractAddress1155,
  tokenId1155,
} from "./config";

// if no referrer, use zero address
const referrer = zeroAddress;

// if no smart wallet owner, use zero address
const smartWallet = zeroAddress;

const sparkValue = parseEther("0.000001");

// comment that we are replying to.  If there is no reply, use emptyCommentIdentifier() from @zoralabs/protocol-deployments
const replyTo = emptyCommentIdentifier();
// comment on token, paying the value of 1 spark to the contract
const hash = await walletClient.writeContract({
  abi: commentsABI,
  address: commentsAddress[chainId],
  functionName: "comment",
  args: [
    // account that is attributed with the comment; must match the account that is executing the transaction
    commenterAccount,
    // 1155 contract address to comment on.  Must be an admin or owner of the token.
    contractAddress1155,
    // tokenId of the token to comment on
    tokenId1155,
    // text content of the comment
    "This is a test comment",
    // empty reply to, since were not replying to any other comment
    replyTo,
    // optional smart wallet. smart wallet can be an owner or creator of the 1155 token.
    // and eoa that is the owner of the smart wallet can comment.
    smartWallet,
    // Optional referrer address to receive a portion of the sparks value
    referrer,
  ],
  // account that is executing the transaction. Must match the commenterAccount argument above.
  account: commenterAccount,
  // pay the value of 1 spark to the contract
  value: sparkValue,
});

// wait for comment to complete - make sure it succeeds
const receipt = await publicClient.waitForTransactionReceipt({ hash });
if (receipt.status !== "success") {
  throw new Error("Transaction failed");
}

// we can get the comment identifier from the Commented event in the receipt logs
const commentedEvent = parseEventLogs({
  abi: commentsABI,
  eventName: "Commented",
  logs: receipt.logs,
})[0]!;

const commentIdentifier = commentedEvent.args.commentIdentifier;

export { commentIdentifier };
