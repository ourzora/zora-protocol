import { Account, Address, encodeAbiParameters } from "viem";
import {
  secondarySwapAddress,
  zoraCreator1155ImplABI,
  safeTransferSwapAbiParameters,
  secondarySwapABI,
  callerAndCommenterABI,
  callerAndCommenterAddress,
} from "@zoralabs/protocol-deployments";
import { makeContractParameters, PublicClient } from "src/utils";
import { getUniswapQuote } from "./uniswap/uniswapQuote";
import { calculateSlippageUp, calculateSlippageDown } from "./slippage";
import { getSecondaryInfo } from "./utils";
import { addressOrAccountAddress } from "src/utils";
import { SimulateContractParametersWithAccount } from "src/types";
import {
  QuotePrice,
  BuyWithSlippageInput,
  SellWithSlippageInput,
  SecondaryInfo,
} from "./types";

// uniswap's auto slippage for L2s is 0.5% -> 0.005
const UNISWAP_SLIPPAGE = 0.005;

// Error constants
const ERROR_INSUFFICIENT_WALLET_FUNDS = "Insufficient wallet funds";
const ERROR_INSUFFICIENT_POOL_SUPPLY = "Insufficient pool supply";
const ERROR_SECONDARY_NOT_CONFIGURED =
  "Secondary not configured for given contract and token";
export const ERROR_SECONDARY_NOT_STARTED = "Secondary market has not started";
export const ERROR_RECIPIENT_MISMATCH =
  "Recipient must be the same as the caller if there is a comment";

// Helper function to create error objects
function makeError(errorMessage: string) {
  return { error: errorMessage };
}

type Call =
  | {
      // Parameters for the buy or sell transaction
      parameters: SimulateContractParametersWithAccount;
      error?: undefined;
    }
  | {
      parameters?: undefined;
      // Error message if the buy or sell operation cannot be performed
      error: string;
    };

async function makeBuy({
  contract,
  tokenId,
  erc20z,
  poolBalance,
  amount,
  quantity,
  account,
  recipient,
  slippage,
  publicClient,
  comment,
}: {
  erc20z: Address;
  contract: Address;
  tokenId: bigint;
  poolBalance: { erc20z: bigint };
  amount: bigint;
  quantity: bigint;
  account: Address | Account;
  recipient?: Address;
  slippage: number;
  comment: string | undefined;
  publicClient: PublicClient;
}): Promise<Call> {
  const costWithSlippage = calculateSlippageUp(amount, slippage);
  const accountAddress = addressOrAccountAddress(account);

  const validationResult = await validateBuyConditions({
    poolBalance,
    quantity,
    costWithSlippage,
    accountAddress,
    publicClient,
  });

  if (validationResult.error) {
    return makeError(validationResult.error);
  }

  if (comment && comment !== "") {
    return handleBuyWithComment({
      accountAddress,
      recipient,
      chainId: publicClient.chain.id,
      quantity,
      contract,
      tokenId,
      costWithSlippage,
      comment,
      account,
    });
  }

  return handleBuyWithoutComment({
    erc20z,
    quantity,
    recipient,
    accountAddress,
    costWithSlippage,
    chainId: publicClient.chain.id,
    account,
  });
}

async function validateBuyConditions({
  poolBalance,
  quantity,
  costWithSlippage,
  accountAddress,
  publicClient,
}: {
  poolBalance: { erc20z: bigint };
  quantity: bigint;
  costWithSlippage: bigint;
  accountAddress: Address;
  publicClient: PublicClient;
}): Promise<{ error?: string }> {
  const availableToBuy = poolBalance.erc20z / BigInt(1e18) - 1n;
  const availableToSpend = await publicClient.getBalance({
    address: accountAddress,
  });

  if (costWithSlippage > availableToSpend) {
    return { error: ERROR_INSUFFICIENT_WALLET_FUNDS };
  }

  if (availableToBuy < BigInt(quantity)) {
    return { error: ERROR_INSUFFICIENT_POOL_SUPPLY };
  }

  return {};
}

function handleBuyWithComment({
  accountAddress,
  recipient,
  chainId,
  quantity,
  contract,
  tokenId,
  costWithSlippage,
  comment,
  account,
}: {
  accountAddress: Address;
  recipient?: Address;
  chainId: number;
  quantity: bigint;
  contract: Address;
  tokenId: bigint;
  costWithSlippage: bigint;
  comment: string;
  account: Address | Account;
}): Call {
  if (recipient && recipient !== accountAddress) {
    return makeError(ERROR_RECIPIENT_MISMATCH);
  }

  return {
    parameters: makeContractParameters({
      abi: callerAndCommenterABI,
      address:
        callerAndCommenterAddress[
          chainId as keyof typeof callerAndCommenterAddress
        ],
      functionName: "buyOnSecondaryAndComment",
      args: [
        accountAddress,
        quantity,
        contract,
        tokenId,
        accountAddress,
        costWithSlippage,
        0n,
        comment,
      ],
      account,
      value: costWithSlippage,
    }),
  };
}

function handleBuyWithoutComment({
  erc20z,
  quantity,
  recipient,
  accountAddress,
  costWithSlippage,
  chainId,
  account,
}: {
  erc20z: Address;
  quantity: bigint;
  recipient?: Address;
  accountAddress: Address;
  costWithSlippage: bigint;
  chainId: number;
  account: Address | Account;
}): Call {
  return {
    parameters: makeContractParameters({
      abi: secondarySwapABI,
      address:
        secondarySwapAddress[chainId as keyof typeof secondarySwapAddress],
      functionName: "buy1155",
      args: [
        erc20z,
        quantity,
        recipient || accountAddress,
        accountAddress,
        costWithSlippage,
        0n,
      ],
      account,
      value: costWithSlippage,
    }),
  };
}

type BuyOrSellWithSlippageResult =
  | ({
      // Price to buy or sell the quantity of 1155s
      price: QuotePrice;
    } & Call)
  | {
      error: string;
      price?: undefined;
      parameters?: undefined;
    };

export async function buy1155OnSecondary({
  contract,
  tokenId,
  publicClient,
  quantity,
  account,
  slippage = UNISWAP_SLIPPAGE,
  recipient,
  comment,
}: BuyWithSlippageInput & {
  publicClient: PublicClient;
}): Promise<BuyOrSellWithSlippageResult> {
  const secondaryInfo = await getSecondaryInfo({
    contract,
    tokenId,
    publicClient,
  });

  if (!secondaryInfo) {
    return makeError(ERROR_SECONDARY_NOT_CONFIGURED);
  }

  const { erc20z, pool, secondaryActivated } = secondaryInfo;

  if (!secondaryActivated) {
    return makeError(ERROR_SECONDARY_NOT_STARTED);
  }

  const { poolBalance, amount, price } = await getUniswapQuote(
    {
      type: "buy",
      quantity,
      poolAddress: pool,
      erc20z,
    },
    publicClient,
  );

  const call = await makeBuy({
    erc20z,
    contract,
    tokenId,
    poolBalance,
    amount,
    quantity,
    account,
    recipient,
    slippage,
    comment,
    publicClient,
  });

  return {
    ...call,
    price,
  };
}

async function makeSell({
  contract,
  tokenId,
  poolBalance,
  amount,
  quantity,
  account,
  recipient,
  slippage,
  publicClient,
}: {
  contract: Address;
  tokenId: bigint;
  poolBalance: { weth: bigint };
  amount: bigint;
  quantity: bigint;
  account: Address | Account;
  recipient?: Address;
  slippage: number;
  publicClient: PublicClient;
}): Promise<Call> {
  const accountAddress = addressOrAccountAddress(account);

  const tokenCount = await publicClient.readContract({
    abi: zoraCreator1155ImplABI,
    address: contract,
    functionName: "balanceOf",
    args: [accountAddress, tokenId],
  });

  const availableToSell = tokenCount ?? 0n;
  const availableToReceive = poolBalance.weth;

  if (quantity > availableToSell) {
    return makeError(ERROR_INSUFFICIENT_WALLET_FUNDS);
  }

  if (amount > availableToReceive) {
    return makeError(ERROR_INSUFFICIENT_POOL_SUPPLY);
  }

  const receivedWithSlippage = calculateSlippageDown(amount, slippage);

  const data = encodeAbiParameters(safeTransferSwapAbiParameters, [
    recipient || accountAddress,
    receivedWithSlippage,
    0n,
  ]);

  const chainId = publicClient.chain.id;

  return {
    parameters: makeContractParameters({
      abi: zoraCreator1155ImplABI,
      address: contract,
      functionName: "safeTransferFrom",
      account,
      args: [
        accountAddress,
        secondarySwapAddress[chainId as keyof typeof secondarySwapAddress],
        tokenId,
        quantity,
        data,
      ],
    }),
  };
}

export async function sell1155OnSecondary({
  contract,
  tokenId,
  publicClient,
  quantity,
  account,
  slippage = UNISWAP_SLIPPAGE,
  recipient,
}: SellWithSlippageInput & {
  publicClient: PublicClient;
}): Promise<BuyOrSellWithSlippageResult> {
  const secondaryInfo = await getSecondaryInfo({
    contract,
    tokenId,
    publicClient,
  });

  if (!secondaryInfo) {
    return makeError(ERROR_SECONDARY_NOT_CONFIGURED);
  }

  const { pool, secondaryActivated, erc20z } = secondaryInfo;

  if (!secondaryActivated) {
    return makeError(ERROR_SECONDARY_NOT_STARTED);
  }

  const { poolBalance, amount, price } = await getUniswapQuote(
    { type: "sell", quantity, poolAddress: pool, erc20z },
    publicClient,
  );

  const call = await makeSell({
    contract,
    tokenId,
    poolBalance,
    amount,
    quantity,
    account,
    recipient,
    slippage,
    publicClient,
  });

  return {
    ...call,
    price,
  };
}

/**
 * @deprecated Please use functions directly without creating a client.
 * Example: Instead of `new SecondaryClient().buy1155OnSecondary()`, use `buy1155OnSecondary()`
 * Import the functions you need directly from their respective modules:
 * import { buy1155OnSecondary, sell1155OnSecondary, getSecondaryInfo } from '@zoralabs/protocol-sdk'
 */
export class SecondaryClient {
  private publicClient: PublicClient;

  /**
   * Creates a new SecondaryClient instance.
   * @param publicClient - The public client for interacting with the blockchain.
   * @param chainId - The ID of the blockchain network.
   */
  constructor({ publicClient }: { publicClient: PublicClient }) {
    this.publicClient = publicClient;
  }

  /**
   * Get the secondary info for a given contract and token ID.
   * @param contract - The address of the contract.
   * @param tokenId - The ID of the token.
   * @returns A promise that resolves to the secondary info.
   */
  async getSecondaryInfo({
    contract,
    tokenId,
  }: {
    contract: Address;
    tokenId: bigint;
  }): Promise<SecondaryInfo | undefined> {
    return getSecondaryInfo({
      contract,
      tokenId,
      publicClient: this.publicClient,
    });
  }

  /**
   * Prepares a buy operation with slippage protection for purchasing a quantity of ERC1155 tokens with ETH on the secondary market.
   * @param input - The input parameters for the buy operation.
   * @returns A promise that resolves to the result of the buy operation, including price breakdown and transaction parameters.
   */
  async buy1155OnSecondary(
    input: BuyWithSlippageInput,
  ): Promise<BuyOrSellWithSlippageResult> {
    // Call the buyWithSlippage function with the provided input and client details
    return buy1155OnSecondary({
      ...input,
      publicClient: this.publicClient,
    });
  }

  /**
   * Prepares a sell operation with slippage protection for selling a quantity of ERC1155 tokens for ETH on the secondary market.
   * @param input - The input parameters for the sell operation.
   * @returns A promise that resolves to the result of the sell operation, including price breakdown and transaction parameters.
   */
  async sell1155OnSecondary(
    input: SellWithSlippageInput,
  ): Promise<BuyOrSellWithSlippageResult> {
    // Call the sellWithSlippage function with the provided input and client details
    return sell1155OnSecondary({
      ...input,
      publicClient: this.publicClient,
    });
  }
}
