import {
  coinFactoryAddress,
  coinFactoryABI as zoraFactoryImplABI,
} from "@zoralabs/protocol-deployments";
import {
  Account,
  Address,
  ContractEventArgsFromTopics,
  decodeFunctionData,
  Hex,
  isAddressEqual,
  parseEventLogs,
  TransactionReceipt,
  WalletClient,
} from "viem";
import { BundlerClient } from "viem/account-abstraction";
import { base } from "viem/chains";
import { postCreateContent } from "../api";
import { validateMetadataURIContent } from "../metadata";
import { ValidMetadataURI } from "../uploader/types";
import { GenericCall, toUserOperationCalls } from "../utils/calls";
import { GenericPublicClient } from "../utils/genericPublicClient";
import { getChainFromId } from "../utils/getChainFromId";
import { rethrowDecodedRevert } from "../utils/rethrowDecodedRevert";
import {
  prepareUserOperation,
  submitUserOperation,
} from "../utils/userOperation";
import { validateClientNetwork } from "../utils/validateClientNetwork";

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
  /**
   * Enable smart wallet routing. When true, the API resolves the creator's
   * linked smart wallet and returns a single call wrapped in the smart wallet's
   * `execute`, so the coin is deployed and owned by the smart wallet (executed by
   * an owner EOA). Used by {@link createCoinSmartWallet}. Defaults to false.
   */
  enableSmartWalletRouting?: boolean;
};

type TransactionParameters = {
  to: Address;
  data: Hex;
  value: bigint;
};

type CreateCoinCallResponse = {
  calls: TransactionParameters[];
  predictedCoinAddress: Address;
  /**
   * Whether the API applied smart wallet routing. False (or undefined) means the
   * call targets the factory directly (EOA creation); true means it is wrapped in
   * the smart wallet's `execute`.
   */
  usedSmartWalletRouting?: boolean;
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
  enableSmartWalletRouting,
}: CreateCoinArgs): Promise<CreateCoinCallResponse> {
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
    enableSmartWalletRouting,
  });

  if (!createContentRequest.data?.calls) {
    throw new Error("Failed to create content calldata");
  }

  return {
    calls: createContentRequest.data.calls.map((data) => ({
      to: data.to as Address,
      data: data.data as Hex,
      value: BigInt(data.value),
    })),
    predictedCoinAddress: createContentRequest.data
      .predictedCoinAddress as Address,
    usedSmartWalletRouting: createContentRequest.data.usedSmartWalletRouting,
  };
}

/**
 * Validates the assembled calls for creating a coin.
 *
 * Asserts the invariants this SDK version supports: a single call, targeting the
 * coin factory for the given chain, with no attached value (no buy-on-create).
 * Shared by both the EOA execution path (`createCoin`) and the user-operation
 * path so both validate identically.
 */
export function validateCreateCoinCalls(
  calls: GenericCall[],
  chainId: number,
): void {
  if (calls.length !== 1) {
    throw new Error("Only one call is supported for this SDK version");
  }

  const createContentCall = calls[0];

  if (!createContentCall) {
    throw new Error("Failed to load create content calldata from API");
  }

  const coinFactoryAddressForChain =
    coinFactoryAddress[chainId as keyof typeof coinFactoryAddress];

  // Sanity check that the call is for the correct factory contract
  if (!isAddressEqual(createContentCall.to, coinFactoryAddressForChain)) {
    throw new Error("Creator coin is not supported for this SDK version");
  }

  // Sanity check to ensure no buy orders are sent with these parameters
  if (createContentCall.value !== 0n) {
    throw new Error(
      "Creator coin and purchase is not supported for this SDK version.",
    );
  }
}

/**
 * Validates the assembled calls for creating a coin via smart wallet routing.
 *
 * Unlike {@link validateCreateCoinCalls}, the call targets the creator's smart
 * wallet (its `execute` method), not the factory — so the factory-target check
 * does not apply. The key guard is that the API actually applied routing:
 * `enableSmartWalletRouting` is best-effort and silently falls back to EOA
 * creation when the creator has no linked smart wallet, which must not be
 * mistaken for a smart wallet creation.
 */
export function validateCreateCoinSmartWalletCalls(
  calls: GenericCall[],
  { usedSmartWalletRouting }: { usedSmartWalletRouting?: boolean },
): void {
  if (!usedSmartWalletRouting) {
    throw new Error(
      "Smart wallet routing was not applied. The creator must have a linked smart wallet; otherwise use createCoin for EOA creation.",
    );
  }

  if (calls.length !== 1) {
    throw new Error("Only one call is supported for this SDK version");
  }

  const createContentCall = calls[0];

  if (!createContentCall) {
    throw new Error("Failed to load create content calldata from API");
  }

  // Sanity check to ensure no buy orders are sent with these parameters
  if (createContentCall.value !== 0n) {
    throw new Error(
      "Creator coin and purchase is not supported for this SDK version.",
    );
  }
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

type CreateCoinOptions = {
  gasMultiplier?: number;
  account?: Account | Address;
  skipValidateTransaction?: boolean;
};

/** Minimal ABI for the Coinbase Smart Wallet `execute` method, used to unwrap a routed call. */
const coinbaseSmartWalletExecuteABI = [
  {
    type: "function",
    name: "execute",
    stateMutability: "payable",
    inputs: [
      { name: "target", type: "address" },
      { name: "value", type: "uint256" },
      { name: "data", type: "bytes" },
    ],
    outputs: [],
  },
] as const;

/**
 * Unwraps the smart wallet `execute(target, value, data)` call that the API
 * returns under smart wallet routing into its inner factory call.
 *
 * The bundler/account (`toCoinbaseSmartAccount.encodeCalls`) re-wraps a single
 * call in `execute` when forming the user operation, so the inner call — not the
 * pre-wrapped one — must be fed to the user-operation path; passing the wrapped
 * call would double-wrap it. The inner call still executes with the smart wallet
 * as `msg.sender`, so the deployed coin's CREATE2 address is unchanged (the API's
 * predicted address remains valid).
 *
 * Throws if the call is not a recognizable `execute` call, so an unexpected shape
 * fails loudly rather than silently double-wrapping.
 */
function unwrapSmartWalletExecuteCall(call: GenericCall): GenericCall {
  let decoded;
  try {
    decoded = decodeFunctionData({
      abi: coinbaseSmartWalletExecuteABI,
      data: call.data,
    });
  } catch {
    throw new Error(
      "Expected a smart wallet `execute` call from smart wallet routing, but the routed call could not be decoded.",
    );
  }

  const [target, value, data] = decoded.args;
  return { to: target, value, data };
}

/**
 * Selects the account used to sign and send the create transaction.
 *
 * Prefers a LocalAccount from the wallet client when available to ensure offline
 * signing (eth_sendRawTransaction) instead of wallet_sendTransaction, which can
 * error when a `from` field is present.
 */
function selectExecutionAccount(
  walletClient: WalletClient,
  account?: Account | Address,
): Account {
  const selected =
    (typeof account === "string" ? undefined : account) ?? walletClient.account;

  if (!selected) {
    throw new Error("Account is required");
  }

  return selected;
}

/**
 * Simulates, gas-estimates, sends and awaits a single create call, then parses
 * the deployment from the receipt logs. Shared by {@link createCoin} (factory
 * call) and {@link createCoinSmartWallet} (smart wallet `execute` call) so both
 * return the same shape.
 */
async function executeCreateContentCall({
  createContentCall,
  account,
  walletClient,
  publicClient,
  skipValidateTransaction,
}: {
  createContentCall: GenericCall;
  account: Account;
  walletClient: WalletClient;
  publicClient: GenericPublicClient;
  skipValidateTransaction?: boolean;
}) {
  const viemCall = {
    ...createContentCall,
    account,
  };

  // simulate call
  if (!skipValidateTransaction) {
    try {
      await publicClient.call(viemCall);
    } catch (err) {
      rethrowDecodedRevert(err, zoraFactoryImplABI);
    }
  }

  const gasEstimate = skipValidateTransaction
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
  options?: CreateCoinOptions;
}) {
  validateClientNetwork(publicClient);

  const chainId = call.chainId ?? publicClient.chain.id;

  const { calls } = await createCoinCall({
    ...call,
    chainId,
  });

  validateCreateCoinCalls(calls, chainId);

  const createContentCall = calls[0]!;

  const account = selectExecutionAccount(walletClient, options?.account);

  return executeCreateContentCall({
    createContentCall,
    account,
    walletClient,
    publicClient,
    skipValidateTransaction: options?.skipValidateTransaction,
  });
}

/**
 * Creates a coin owned by the caller's smart wallet via a user operation.
 *
 * Requests smart wallet routing from the API, which resolves the creator's
 * linked smart wallet and returns the deploy wrapped in the smart wallet's
 * `execute`. That wrapped call is unwrapped to its inner factory call and
 * submitted as a user operation through `bundlerClient` — so the smart wallet
 * deploys and owns the coin while gas is paid from the smart wallet's
 * user-operation prefund (rather than from an owner EOA). The bundler/account
 * re-wraps the inner call in `execute` itself, and the smart wallet remains
 * `msg.sender`, so the deployed coin's CREATE2 address matches the API's
 * prediction.
 *
 * Mirrors {@link createCoin}'s return shape. Throws if the API did not apply
 * routing (e.g. the creator has no linked smart wallet) — use {@link createCoin}
 * for EOA creation in that case.
 */
export async function createCoinSmartWallet({
  call,
  bundlerClient,
  publicClient,
}: {
  call: CreateCoinArgs;
  bundlerClient: BundlerClient;
  publicClient: GenericPublicClient;
  // `options` is accepted for signature parity with createCoin but does not
  // apply to the user-operation path: the account comes from the bundler client,
  // and gas/validation are handled by the bundler during preparation.
  options?: CreateCoinOptions;
}) {
  validateClientNetwork(publicClient);

  const account = bundlerClient.account;
  if (!account) {
    throw new Error("Account is required: the bundler client has no account");
  }

  const chainId = call.chainId ?? publicClient.chain.id;

  const { calls, usedSmartWalletRouting } = await createCoinCall({
    ...call,
    chainId,
    enableSmartWalletRouting: true,
  });

  validateCreateCoinSmartWalletCalls(calls, { usedSmartWalletRouting });

  // Unwrap the routed `execute` call so the bundler re-wraps the inner call
  // itself instead of double-wrapping (see unwrapSmartWalletExecuteCall).
  const innerCall = unwrapSmartWalletExecuteCall(calls[0]!);

  const userOperation = await prepareUserOperation({
    bundlerClient,
    account,
    calls: toUserOperationCalls([innerCall]),
  });

  const userOpReceipt = await submitUserOperation({
    bundlerClient,
    account,
    userOperation,
  });

  if (!userOpReceipt.success) {
    throw new Error(
      `User operation reverted${userOpReceipt.reason ? `: ${userOpReceipt.reason}` : ""}`,
    );
  }

  // Parse the deployment from this user operation's own logs (not the whole
  // bundle's), so a co-bundled CoinCreatedV4 can't be misattributed.
  const eventLogs = parseEventLogs({
    abi: zoraFactoryImplABI,
    logs: userOpReceipt.logs,
  });
  const deployment = eventLogs.find(
    (log) => log.eventName === "CoinCreatedV4",
  )?.args;

  return {
    hash: userOpReceipt.receipt.transactionHash,
    receipt: userOpReceipt.receipt,
    address: deployment?.coin,
    deployment,
    chain: getChainFromId(publicClient.chain.id),
  };
}
