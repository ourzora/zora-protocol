import { coinABI } from "@zoralabs/protocol-deployments";
import {
  Account,
  Address,
  parseEventLogs,
  SimulateContractParameters,
  WalletClient,
} from "viem";
import { BundlerClient, SmartAccount } from "viem/account-abstraction";
import { getAttribution } from "../utils/attribution";
import { toGenericCall, toUserOperationCalls } from "../utils/calls";
import { GenericPublicClient } from "../utils/genericPublicClient";
import {
  prepareUserOperation,
  submitUserOperation,
} from "../utils/userOperation";
import { validateClientNetwork } from "../utils/validateClientNetwork";

export type UpdateCoinURIArgs = {
  coin: Address;
  newURI: string;
};

/**
 * Validates the arguments for updating a coin's URI.
 *
 * Asserts the new URI is an `ipfs://` URI. Shared by the contract-call builder
 * (`updateCoinURICall`) and the user-operation path so both validate identically.
 */
export function validateUpdateCoinURI({ newURI }: UpdateCoinURIArgs): void {
  if (!newURI.startsWith("ipfs://")) {
    throw new Error("URI needs to be an ipfs:// prefix uri");
  }
}

export function updateCoinURICall(
  args: UpdateCoinURIArgs,
): SimulateContractParameters {
  validateUpdateCoinURI(args);

  const { coin, newURI } = args;

  return {
    abi: coinABI,
    address: coin,
    functionName: "setContractURI",
    args: [newURI],
    dataSuffix: getAttribution(),
  };
}

export async function updateCoinURI(
  args: UpdateCoinURIArgs,
  walletClient: WalletClient,
  publicClient: GenericPublicClient,
  account?: Account | Address,
) {
  validateClientNetwork(publicClient);

  const call = updateCoinURICall(args);

  const { request } = await publicClient.simulateContract({
    ...call,
    account: account ?? walletClient.account,
  });

  const hash = await walletClient.writeContract(request);

  const receipt = await publicClient.waitForTransactionReceipt({ hash });

  const eventLogs = parseEventLogs({ abi: coinABI, logs: receipt.logs });
  const uriUpdated = eventLogs.find(
    (log) => log.eventName === "ContractURIUpdated",
  );

  return { hash, receipt, uriUpdated };
}

/**
 * Updates a coin's URI from the caller's smart wallet via a user operation.
 *
 * Builds the `setContractURI` call, submits it through the bundler client (which
 * wraps it in the smart wallet's `execute`), and parses the result. Mirrors
 * {@link updateCoinURI}'s return shape (`hash` is the settled transaction hash,
 * `receipt` the underlying transaction receipt).
 */
export async function updateCoinURISmartWallet(
  args: UpdateCoinURIArgs,
  bundlerClient: BundlerClient,
  publicClient: GenericPublicClient,
  account?: SmartAccount,
) {
  const resolvedAccount = account ?? bundlerClient.account;
  if (!resolvedAccount) {
    throw new Error("Account is required");
  }

  validateClientNetwork(publicClient);

  // updateCoinURICall validates the args and assembles the contract call
  const call = updateCoinURICall(args);

  const calls = toUserOperationCalls([toGenericCall(call)]);

  const userOp = await prepareUserOperation({
    bundlerClient,
    account: resolvedAccount,
    calls,
  });

  const userOpReceipt = await submitUserOperation({
    bundlerClient,
    account: resolvedAccount,
    userOperation: userOp,
  });

  if (!userOpReceipt.success) {
    throw new Error(
      `User operation reverted${userOpReceipt.reason ? `: ${userOpReceipt.reason}` : ""}`,
    );
  }

  const eventLogs = parseEventLogs({ abi: coinABI, logs: userOpReceipt.logs });
  const uriUpdated = eventLogs.find(
    (log) => log.eventName === "ContractURIUpdated",
  );

  return {
    hash: userOpReceipt.receipt.transactionHash,
    receipt: userOpReceipt.receipt,
    uriUpdated,
  };
}
