import { coinABI } from "@zoralabs/protocol-deployments";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import {
  Account,
  Address,
  isAddress,
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

/**
 * Validates the arguments for updating a coin's payout recipient.
 *
 * Asserts the new payout recipient is a valid address. Shared by the
 * contract-call builder (`updatePayoutRecipientCall`) and the user-operation path
 * so both validate identically.
 */
export function validateUpdatePayoutRecipient({
  newPayoutRecipient,
}: UpdatePayoutRecipientArgs): void {
  if (!isAddress(newPayoutRecipient)) {
    throw new Error("Payout recipient must be a valid address");
  }
}

export function updatePayoutRecipientCall(
  args: UpdatePayoutRecipientArgs,
): SimulateContractParameters {
  validateUpdatePayoutRecipient(args);

  const { coin, newPayoutRecipient } = args;

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
