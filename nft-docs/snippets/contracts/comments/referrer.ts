import {
  commentsABI,
  commentsAddress,
  emptyCommentIdentifier,
} from "@zoralabs/protocol-deployments";
import { zeroAddress, parseEther } from "viem";
import {
  publicClient,
  walletClient,
  chainId,
  commenterAccount,
  contractAddress1155,
  tokenId1155,
} from "./config";

// referrer is the address that will receive a portion of the Sparks value
const referrer = "0x1234567890123456789012345678901234567890"; // [!code focus]

const sparkValue = parseEther("0.000001");

const replyTo = emptyCommentIdentifier();
// comment on token, paying the value of 1 spark to the contract
const hash = await walletClient.writeContract({
  abi: commentsABI,
  address: commentsAddress[chainId],
  functionName: "comment",
  args: [
    commenterAccount,
    contractAddress1155,
    tokenId1155,
    "This is a test comment",
    replyTo,
    zeroAddress,
    // Optional referrer address to receive a portion of the Sparks value
    referrer, // [!code focus]
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
