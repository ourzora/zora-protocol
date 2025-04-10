import { zoraFactoryImplABI } from "@zoralabs/coins";
import {
  Address,
  TransactionReceipt,
  WalletClient,
  SimulateContractParameters,
  ContractEventArgsFromTopics,
  parseEventLogs,
} from "viem";
import { COIN_FACTORY_ADDRESS } from "../constants";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import { GenericPublicClient } from "src/utils/genericPublicClient";
import { validateMetadataURIContent, ValidMetadataURI } from "src/metadata";

export type CoinDeploymentLogArgs = ContractEventArgsFromTopics<
  typeof zoraFactoryImplABI,
  "CoinCreated"
>;

export type CreateCoinArgs = {
  name: string;
  symbol: string;
  uri: ValidMetadataURI;
  owners?: Address[];
  tickLower?: number;
  payoutRecipient: Address;
  platformReferrer?: Address;
  initialPurchaseWei?: bigint;
};

export async function createCoinCall({
  name,
  symbol,
  uri,
  owners,
  payoutRecipient,
  initialPurchaseWei = 0n,
  tickLower = -208200,
  platformReferrer = "0x0000000000000000000000000000000000000000",
}: CreateCoinArgs): Promise<
  SimulateContractParameters<typeof zoraFactoryImplABI, "deploy">
> {
  if (!owners) {
    owners = [payoutRecipient];
  }

  // This will throw an error if the metadata is not valid
  await validateMetadataURIContent(uri);

  // For now, we only support the base currency as WETH
  const currency = "0x4200000000000000000000000000000000000006";
  return {
    abi: zoraFactoryImplABI,
    functionName: "deploy",
    address: COIN_FACTORY_ADDRESS,
    args: [
      payoutRecipient,
      owners,
      uri,
      name,
      symbol,
      platformReferrer,
      currency,
      tickLower,
      initialPurchaseWei,
    ],
    value: initialPurchaseWei,
  } as const;
}

/**
 * Gets the deployed coin address from transaction receipt logs
 * @param receipt Transaction receipt containing the CoinCreated event
 * @returns The deployment information if found
 */
export function getCoinCreateFromLogs(
  receipt: TransactionReceipt,
): CoinDeploymentLogArgs | undefined {
  const eventLogs = parseEventLogs({
    abi: zoraFactoryImplABI,
    logs: receipt.logs,
  });
  return eventLogs.find((log) => log.eventName === "CoinCreated")?.args;
}

// Update createCoin to return both receipt and coin address
export async function createCoin(
  call: CreateCoinArgs,
  walletClient: WalletClient,
  publicClient: GenericPublicClient,
  options?: {
    gasMultiplier?: number;
  },
) {
  validateClientNetwork(publicClient);

  const createCoinRequest = await createCoinCall(call);
  const { request } = await publicClient.simulateContract({
    ...createCoinRequest,
    account: walletClient.account,
  });

  // Add a 2/5th buffer on gas.
  if (request.gas) {
    // Gas limit multiplier is a percentage argument.
    request.gas = (request.gas * BigInt(options?.gasMultiplier ?? 100)) / 100n;
  }
  const hash = await walletClient.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  const deployment = getCoinCreateFromLogs(receipt);

  return {
    hash,
    receipt,
    address: deployment?.coin,
    deployment,
  };
}
