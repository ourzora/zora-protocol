import { coinABI } from "@zoralabs/protocol-deployments";
import {
  Account,
  Address,
  isAddress,
  parseEventLogs,
  SimulateContractParameters,
  WalletClient,
} from "viem";
import { BundlerClient, SmartAccount } from "viem/account-abstraction";
import { getAttribution } from "../utils/attribution";
import { toGenericCall, toUserOperationCalls } from "../utils/calls";
import { GenericPublicClient } from "../utils/genericPublicClient";
import { validateClientNetwork } from "../utils/validateClientNetwork";

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

/**
 * Updates a coin's payout recipient from the caller's smart wallet via a user
 * operation.
 *
 * Builds the `setPayoutRecipient` call, submits it through the bundler client
 * (which wraps it in the smart wallet's `execute`), and parses the result.
 * Mirrors {@link updatePayoutRecipient}'s return shape (`hash` is the settled
 * transaction hash, `receipt` the underlying transaction receipt).
 */
export async function updatePayoutRecipientSmartWallet(
  args: UpdatePayoutRecipientArgs,
  bundlerClient: BundlerClient,
  publicClient: GenericPublicClient,
  account?: SmartAccount,
) {
  validateClientNetwork(publicClient);

  // updatePayoutRecipientCall validates the args and assembles the contract call
  const call = updatePayoutRecipientCall(args);

  const calls = toUserOperationCalls([toGenericCall(call)]);

  const userOpHash = await bundlerClient.sendUserOperation({
    account: account ?? bundlerClient.account!,
    calls,
  });

  const userOpReceipt = await bundlerClient.waitForUserOperationReceipt({
    hash: userOpHash,
  });

  if (!userOpReceipt.success) {
    throw new Error(
      `User operation reverted${userOpReceipt.reason ? `: ${userOpReceipt.reason}` : ""}`,
    );
  }

  const eventLogs = parseEventLogs({ abi: coinABI, logs: userOpReceipt.logs });
  const payoutRecipientUpdated = eventLogs.find(
    (log) => log.eventName === "CoinPayoutRecipientUpdated",
  );

  return {
    hash: userOpReceipt.receipt.transactionHash,
    receipt: userOpReceipt.receipt,
    payoutRecipientUpdated,
  };
}
