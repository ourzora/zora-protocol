import {
  coinFactoryAddress,
  coinFactoryABI as zoraFactoryImplABI,
} from "@zoralabs/protocol-deployments";
import {
  Address,
  TransactionReceipt,
  WalletClient,
  ContractEventArgsFromTopics,
  parseEventLogs,
  Hex,
  Account,
  isAddressEqual,
} from "viem";
import { base } from "viem/chains";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import { GenericPublicClient } from "../utils/genericPublicClient";
import { validateMetadataURIContent } from "../metadata";
import { ValidMetadataURI } from "../uploader/types";
import { getChainFromId } from "../utils/getChainFromId";
import { postCreateContent } from "../api";
import { rethrowDecodedRevert } from "../utils/rethrowDecodedRevert";

export type CoinDeploymentLogArgs = ContractEventArgsFromTopics<
  typeof zoraFactoryImplABI,
  "CoinCreatedV4"
>;

const STARTING_MARKET_CAPS = {
  LOW: "LOW",
  HIGH: "HIGH",
} as const;
export type StartingMarketCap = keyof typeof STARTING_MARKET_CAPS;

export interface RawUriMetadata {
  type: "RAW_URI";
  uri: string;
}

const CONTENT_COIN_CURRENCIES = {
  CREATOR_COIN: "CREATOR_COIN",
  ZORA: "ZORA",
  ETH: "ETH",
  CREATOR_COIN_OR_ZORA: "CREATOR_COIN_OR_ZORA",
} as const;
export type ContentCoinCurrency = keyof typeof CONTENT_COIN_CURRENCIES;

export const CreateConstants = {
  StartingMarketCaps: STARTING_MARKET_CAPS,
  ContentCoinCurrencies: CONTENT_COIN_CURRENCIES,
} as const;

export type CreateCoinArgs = {
  creator: string;
  name: string;
  symbol: string;
  metadata: RawUriMetadata;
  currency: ContentCoinCurrency;
  chainId?: number;
  startingMarketCap?: StartingMarketCap;
  platformReferrer?: string;
  additionalOwners?: Address[];
  payoutRecipientOverride?: Address;
  skipMetadataValidation?: boolean;
};

type TransactionParameters = {
  to: Address;
  data: Hex;
  value: bigint;
};

export async function createCoinCall({
  creator,
  name,
  symbol,
  metadata,
  currency,
  chainId = base.id,
  payoutRecipientOverride,
  additionalOwners,
  platformReferrer,
  skipMetadataValidation = false,
}: CreateCoinArgs): Promise<TransactionParameters[]> {
  // Validate metadata URI
  if (!skipMetadataValidation) {
    await validateMetadataURIContent(metadata.uri as ValidMetadataURI);
  }

  const createContentRequest = await postCreateContent({
    currency,
    chainId,
    metadata,
    creator,
    name,
    symbol,
    platformReferrer,
    additionalOwners,
    payoutRecipientOverride,
  });

  if (!createContentRequest.data?.calls) {
    throw new Error("Failed to create content calldata");
  }

  return createContentRequest.data.calls.map((data) => ({
    to: data.to as Address,
    data: data.data as Hex,
    value: BigInt(data.value),
  }));
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
export async function createCoin({
  call,
  walletClient,
  publicClient,
  options,
}: {
  call: CreateCoinArgs;
  walletClient: WalletClient;
  publicClient: GenericPublicClient;
  options?: {
    gasMultiplier?: number;
    account?: Account | Address;
    skipValidateTransaction?: boolean;
  };
}) {
  validateClientNetwork(publicClient);

  const chainId = call.chainId ?? publicClient.chain.id;

  const callRequest = await createCoinCall({
    ...call,
    chainId,
  });

  if (callRequest.length !== 1) {
    throw new Error("Only one call is supported for this SDK version");
  }

  const createContentCall = callRequest[0];

  if (!createContentCall) {
    throw new Error("Failed to load create content calldata from API");
  }

  const coinFactoryAddressForChain =
    coinFactoryAddress[call.chainId as keyof typeof coinFactoryAddress];

  // Sanity check that the call is for the correct factory contract
  if (!isAddressEqual(createContentCall.to, coinFactoryAddressForChain)) {
    throw new Error("Creator coin is not supported for this SDK version");
  }

  // Sanity check to ensure no buy orders are sent with there parameters
  if (createContentCall.value !== 0n) {
    throw new Error(
      "Creator coin and purchase is not supported for this SDK version.",
    );
  }

  // Prefer a LocalAccount from the wallet client when available to ensure
  // offline signing (eth_sendRawTransaction) instead of wallet_sendTransaction
  // which can error when a `from` field is present.
  const selectedAccount =
    (typeof options?.account === "string" ? undefined : options?.account) ??
    walletClient.account;

  if (!selectedAccount) {
    throw new Error("Account is required");
  }

  const viemCall = {
    ...createContentCall,
    account: selectedAccount,
  };

  // simulate call
  if (!options?.skipValidateTransaction) {
    try {
      await publicClient.call(viemCall);
    } catch (err) {
      rethrowDecodedRevert(err, zoraFactoryImplABI);
    }
  }

  const gasEstimate = options?.skipValidateTransaction
    ? 10_000_000n
    : await publicClient.estimateGas(viemCall);
  const gasPrice = await publicClient.getGasPrice();

  const hash = await (async () => {
    try {
      return await walletClient.sendTransaction({
        ...viemCall,
        gasPrice,
        gas: gasEstimate,
        chain: publicClient.chain,
      });
    } catch (err) {
      rethrowDecodedRevert(err, zoraFactoryImplABI);
    }
  })();

  const receipt = await publicClient.waitForTransactionReceipt({
    hash,
  });

  const deployment = getCoinCreateFromLogs(receipt);

  return {
    hash,
    receipt,
    address: deployment?.coin,
    deployment,
    chain: getChainFromId(publicClient.chain.id),
  };
}
