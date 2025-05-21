import {
  callerAndCommenterABI,
  callerAndCommenterAddress,
} from "@zoralabs/protocol-deployments";
import {
  publicClient,
  walletClient,
  chainId,
  minterAccount,
  contractAddress1155,
  tokenId1155,
} from "./config";
import { parseEther, zeroAddress } from "viem";

const mintFee = parseEther("0.000111");

const commenter = minterAccount;
const quantityToMint = 3n;
const collection = contractAddress1155;
const tokenId = tokenId1155;
const mintReferral = zeroAddress;
const comment = "This is a test comment";

// minting and commenting in one transaction, calling the `timedSaleMintAndComment` function
// on the `CallerAndCommenter` contract
const hash = await walletClient.writeContract({
  abi: callerAndCommenterABI,
  address: callerAndCommenterAddress[chainId],
  functionName: "timedSaleMintAndComment",
  args: [commenter, quantityToMint, collection, tokenId, mintReferral, comment],
  account: commenter,
  // when minting and commenting, only the mint fee needs to be paid;
  // no additional ETH is required to pay for commenting
  value: mintFee * quantityToMint,
});

const receipt = await publicClient.waitForTransactionReceipt({ hash });
if (receipt.status !== "success") {
  throw new Error("Transaction failed");
}
