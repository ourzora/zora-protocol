import { createCreatorClient } from "@zoralabs/protocol-sdk";
import {
  creatorAccount,
  chainId,
  publicClient,
  walletClient,
  randomAccount,
} from "./config";

const creatorClient = createCreatorClient({ chainId, publicClient });

// prepare a transaction to withdraw Protocol Rewards and Secondary Royalties
const { parameters } = await creatorClient.withdrawRewards({
  // account that holds the balance to withdraw for.  Any outstanding eth or erc20 balance
  // will be transferred to that account.
  withdrawFor: creatorAccount!,
  // set this to false to disable claiming secondary royalties
  claimSecondaryRoyalties: true,
  // account to execute the transaction. Any account can withdraw rewards for another account,
  // but the the rewards will always be pulled to the account that holds the balance
  account: randomAccount,
});

// simulate the transaction
const hash = await walletClient.writeContract(parameters);

// execute the transaction
const receipt = await publicClient.waitForTransactionReceipt({ hash });

if (receipt.status !== "success") {
  throw new Error("transaction failed");
}
