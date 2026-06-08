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
