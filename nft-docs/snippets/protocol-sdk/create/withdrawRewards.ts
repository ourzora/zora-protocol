import { withdrawRewards } from "@zoralabs/protocol-sdk";
import {
  creatorAccount,
  publicClient,
  walletClient,
  randomAccount,
} from "./config";

// prepare a transaction to withdraw Protocol Rewards and Secondary Royalties
const { parameters } = await withdrawRewards({
  // account that holds the balance to withdraw for.  Any outstanding eth or erc20 balance
  // will be transferred to that account.
  withdrawFor: creatorAccount!,
  // set this to false to disable claiming secondary royalties
  claimSecondaryRoyalties: true,
  // account to execute the transaction. Any account can withdraw rewards for another account,
  // but the rewards will always be pulled to the account that holds the balance
  account: randomAccount,
  publicClient,
});

// simulate the transaction
const hash = await walletClient.writeContract(parameters);

// execute the transaction
const receipt = await publicClient.waitForTransactionReceipt({ hash });

if (receipt.status !== "success") {
  throw new Error("transaction failed");
}
