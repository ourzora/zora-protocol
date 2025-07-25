import { coinFactoryABI as zoraFactoryImplABI } from "@zoralabs/protocol-deployments";
import {
  Address,
  TransactionReceipt,
  WalletClient,
  SimulateContractParameters,
  ContractEventArgsFromTopics,
  parseEventLogs,
  zeroAddress,
  keccak256,
  toBytes,
  Hex,
  Account,
} from "viem";
import { base, baseSepolia } from "viem/chains";
import { COIN_FACTORY_ADDRESS } from "../constants";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import { GenericPublicClient } from "../utils/genericPublicClient";
import { validateMetadataURIContent } from "../metadata";
import { ValidMetadataURI } from "../uploader/types";
import { getAttribution } from "../utils/attribution";
import {
  COIN_ETH_PAIR_POOL_CONFIG,
  COIN_ZORA_PAIR_POOL_CONFIG,
} from "../utils/poolConfigUtils";
import { getPrepurchaseHook } from "../utils/getPrepurchaseHook";
import { getChainFromId } from "../utils/getChainFromId";

export type CoinDeploymentLogArgs = ContractEventArgsFromTopics<
  typeof zoraFactoryImplABI,
  "CoinCreatedV4"
>;

export enum DeployCurrency {
  ZORA = 1,
  ETH = 2,
}

export enum InitialPurchaseCurrency {
  ETH = 1,
  // TODO: Add USDC and ZORA support with signature approvals
}

export type CreateCoinArgs = {
  name: string;
  symbol: string;
  uri: ValidMetadataURI;
  chainId?: number;
  owners?: Address[];
  payoutRecipient: Address;
  platformReferrer?: Address;
  currency?: DeployCurrency;
  initialPurchase?: {
    currency: InitialPurchaseCurrency;
    amount: bigint;
  };
};

function getPoolConfig(currency: DeployCurrency, chainId: number) {
  if (currency === DeployCurrency.ZORA && chainId == baseSepolia.id) {
    throw new Error("ZORA is not supported on Base Sepolia");
  }

  switch (currency) {
    case DeployCurrency.ZORA:
      return COIN_ZORA_PAIR_POOL_CONFIG[
        chainId as keyof typeof COIN_ZORA_PAIR_POOL_CONFIG
      ];
    case DeployCurrency.ETH:
      return COIN_ETH_PAIR_POOL_CONFIG[
        chainId as keyof typeof COIN_ETH_PAIR_POOL_CONFIG
      ];
    default:
      throw new Error("Invalid currency");
  }
}

export async function createCoinCall({
  name,
  symbol,
  uri,
  owners,
  payoutRecipient,
  currency,
  chainId = base.id,
  platformReferrer = "0x0000000000000000000000000000000000000000",
  initialPurchase,
}: CreateCoinArgs): Promise<
  SimulateContractParameters<typeof zoraFactoryImplABI, "deploy">
> {
  if (!owners) {
    owners = [payoutRecipient];
  }

  if (!currency) {
    currency = chainId !== base.id ? DeployCurrency.ETH : DeployCurrency.ZORA;
  }

  const poolConfig = getPoolConfig(currency, chainId);

  // This will throw an error if the metadata is not valid
  await validateMetadataURIContent(uri);

  let deployHook = {
    hook: zeroAddress as Address,
    hookData: "0x" as Hex,
    value: 0n,
  };
  if (initialPurchase) {
    deployHook = await getPrepurchaseHook({
      initialPurchase,
      payoutRecipient,
      chainId,
    });
  }

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
      poolConfig,
      platformReferrer,
      deployHook.hook,
      deployHook.hookData,
      keccak256(toBytes(Math.random().toString())), // coinSalt
    ],
    value: deployHook.value,
    dataSuffix: getAttribution(),
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

  return eventLogs.find((log) => log.eventName === "CoinCreatedV4")?.args;
}

// Update createCoin to return both receipt and coin address
export async function createCoin(
  call: CreateCoinArgs,
  walletClient: WalletClient,
  publicClient: GenericPublicClient,
  options?: {
    gasMultiplier?: number;
    account?: Account | Address;
  },
) {
  validateClientNetwork(publicClient);

  const createCoinRequest = await createCoinCall(call);
  const { request } = await publicClient.simulateContract({
    ...createCoinRequest,
    account: options?.account ?? walletClient.account,
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
    chain: getChainFromId(publicClient.chain.id),
  };
}
