import { publicClient, walletClient, minterAccount } from "./config";
import { mint } from "@zoralabs/protocol-sdk";
import { erc20Abi } from "viem";

// prepare the mint transaction.  If it is an erc20 based mint, the erc20Approval object will be returned
// with info for necessary erc20 approvals
const { parameters, erc20Approval } = await mint({
  tokenContract: "0xCD860870DE521cDb0C5ae89E80bBa057Cd30Bf8C",
  mintType: "1155",
  tokenId: 1n,
  quantityToMint: 3,
  mintComment: "My comment",
  minterAccount,
  publicClient,
});

// request necessary erc20 approvals as returned from the sdk's mint call
const approveHash = await walletClient.writeContract({
  abi: erc20Abi,
  address: erc20Approval!.erc20,
  functionName: "approve",
  args: [erc20Approval!.approveTo, erc20Approval!.quantity],
  account: minterAccount,
});

const receipt = await publicClient.waitForTransactionReceipt({
  hash: approveHash,
});

if (receipt.status !== "success") {
  throw new Error("ERC20 Approval failed");
}

// once the erc20 approval is successful, write the mint transaction to the network
const mintHash = await walletClient.writeContract(parameters);

const mintReceipt = await publicClient.waitForTransactionReceipt({
  hash: mintHash,
});

if (mintReceipt.status !== "success") {
  throw new Error("Mint failed");
}
