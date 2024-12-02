import {
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
  commentsABI,
  commentsAddress,
  emptyCommentIdentifier,
  sparkValue,
} from "@zoralabs/protocol-deployments";

import {
  publicClient,
  walletClient,
  chainId,
  smartWalletOwner,
  contractAddress1155,
  tokenId1155,
  bundlerClient,
  smartWalletAccount,
} from "./config";

import { zeroAddress } from "viem";

// 1. Mint as the smart wallet

// fist perform the mint as the smart wallet via the bundler,  making the
// smart wallet the owner of the token; we simulate it first.
const userOperationResponse = await bundlerClient.prepareUserOperation({
  account: smartWalletAccount,
  calls: [
    {
      abi: zoraTimedSaleStrategyABI,
      to: zoraTimedSaleStrategyAddress[chainId],
      functionName: "mint",
      args: [
        smartWalletAccount.address,
        1n,
        contractAddress1155,
        tokenId1155,
        zeroAddress,
        "0",
      ],
    },
  ],
});

// send the user operation with the bundler
const hash = await bundlerClient.sendUserOperation(userOperationResponse);
// ensure the user operation is accepted
const mintReceipt = await bundlerClient.waitForUserOperationReceipt({ hash });
if (!mintReceipt.success) {
  throw new Error("Mint failed");
}

// 2. Comment as the smart wallet owner

// We comment as an owner of the smart wallet.  The contract allows for commenting
// when a smart wallet owned by an account is the owner of the token.

const referrer = zeroAddress;

// now perform the comment as a smart wallet owner
const commentHash = await walletClient.writeContract({
  abi: commentsABI,
  address: commentsAddress[chainId],
  functionName: "comment",
  args: [
    // commenter account is an account that owns the smart wallet
    smartWalletOwner.address, // [!code focus]
    contractAddress1155,
    tokenId1155,
    "This is a test reply",
    // when replying to a comment, we must pass the comment identifier of the comment we are replying to
    emptyCommentIdentifier(),
    // we set the smart wallet parameter.  the smart wallet can be checked to see if it is the owner of the token
    smartWalletAccount.address, // [!code focus]
    referrer,
  ],
  account: smartWalletOwner, // [!code focus]
  value: sparkValue(),
});

const receipt = await publicClient.waitForTransactionReceipt({
  hash: commentHash,
});
if (receipt.status !== "success") {
  throw new Error("Transaction failed");
}
