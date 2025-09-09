import { coinABI } from "@zoralabs/protocol-deployments";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import {
  Account,
  Address,
  parseEventLogs,
  SimulateContractParameters,
  WalletClient,
} from "viem";
import { GenericPublicClient } from "../utils/genericPublicClient";
import { getAttribution } from "../utils/attribution";

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
    dataSuffix: getAttribution(),
  };
}

export async function updatePayoutRecipient(
  args: UpdatePayoutRecipientArgs,
  walletClient: WalletClient,
  publicClient: GenericPublicClient,
  account?: Account | Address,
) {
  validateClientNetwork(publicClient);
  const call = updatePayoutRecipientCall(args);
  const { request } = await publicClient.simulateContract({
    ...call,
    account: account ?? walletClient.account!,
  });
  const hash = await walletClient.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  const eventLogs = parseEventLogs({ abi: coinABI, logs: receipt.logs });
  const payoutRecipientUpdated = eventLogs.find(
    (log) => log.eventName === "CoinPayoutRecipientUpdated",
  );

  return { hash, receipt, payoutRecipientUpdated };
}
