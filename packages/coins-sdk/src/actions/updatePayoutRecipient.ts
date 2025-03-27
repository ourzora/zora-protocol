import { coinABI } from "@zoralabs/coins";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import {
  Address,
  parseEventLogs,
  SimulateContractParameters,
  WalletClient,
} from "viem";
import { GenericPublicClient } from "src/utils/genericPublicClient";

export type UpdatePayoutRecipientArgs = {
  coin: Address;
  newPayoutRecipient: string;
};

export function updatePayoutRecipientCall({
  newPayoutRecipient,
  coin,
}: UpdatePayoutRecipientArgs): SimulateContractParameters {
  return {
    abi: coinABI,
    address: coin,
    functionName: "setPayoutRecipient",
    args: [newPayoutRecipient],
  };
}

export async function updatePayoutRecipient(
  args: UpdatePayoutRecipientArgs,
  walletClient: WalletClient,
  publicClient: GenericPublicClient,
) {
  validateClientNetwork(publicClient);
  const call = updatePayoutRecipientCall(args);
  const { request } = await publicClient.simulateContract({
    ...call,
    account: walletClient.account!,
  });
  const hash = await walletClient.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  const eventLogs = parseEventLogs({ abi: coinABI, logs: receipt.logs });
  const payoutRecipientUpdated = eventLogs.find(
    (log) => log.eventName === "CoinPayoutRecipientUpdated",
  );

  return { hash, receipt, payoutRecipientUpdated };
}
