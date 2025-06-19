import { coinABI } from "@zoralabs/protocol-deployments";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import {
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

export function updateCoinURICall({
  newURI,
  coin,
}: UpdateCoinURIArgs): SimulateContractParameters {
  if (!newURI.startsWith("ipfs://")) {
    throw new Error("URI needs to be an ipfs:// prefix uri");
  }

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
) {
  validateClientNetwork(publicClient);
  const call = updateCoinURICall(args);
  const { request } = await publicClient.simulateContract({
    ...call,
    account: walletClient.account!,
  });
  const hash = await walletClient.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  const eventLogs = parseEventLogs({ abi: coinABI, logs: receipt.logs });
  const uriUpdated = eventLogs.find(
    (log) => log.eventName === "ContractURIUpdated",
  );

  return { hash, receipt, uriUpdated };
}
