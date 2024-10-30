import { Account, Address, encodeAbiParameters } from "viem";
import {
  secondarySwapAddress,
  zoraCreator1155ImplABI,
  safeTransferSwapAbiParameters,
  secondarySwapABI,
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
  erc20z,
  poolBalance,
  amount,
  quantity,
  account,
  recipient,
  chainId,
  slippage,
  publicClient,
}: {
  erc20z: Address;
  poolBalance: { erc20z: bigint };
  amount: bigint;
  quantity: bigint;
  account: Address | Account;
  recipient?: Address;
  chainId: number;
  slippage: number;
  publicClient: PublicClient;
}): Promise<Call> {
  const costWithSlippage = calculateSlippageUp(amount, slippage);

  // we cannot buy all the available tokens in a pool (the quote fails if we try doing that)
  const availableToBuy = poolBalance.erc20z / BigInt(1e18) - 1n;

  const accountAddress = addressOrAccountAddress(account);

  const availableToSpend = await publicClient.getBalance({
    address: accountAddress,
  });

  if (costWithSlippage > availableToSpend) {
    return makeError(ERROR_INSUFFICIENT_WALLET_FUNDS);
  }

  if (availableToBuy < BigInt(quantity)) {
    return makeError(ERROR_INSUFFICIENT_POOL_SUPPLY);
  }

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
      account: account,
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

export async function buyWithSlippage({
  contract,
  tokenId,
  publicClient,
  quantity,
  chainId,
  account,
  slippage = UNISWAP_SLIPPAGE,
  recipient,
}: BuyWithSlippageInput & {
  chainId: number;
  publicClient: PublicClient;
}): Promise<BuyOrSellWithSlippageResult> {
  const secondaryInfo = await getSecondaryInfo({
    contract,
    tokenId,
    publicClient,
    chainId,
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
      chainId,
    },
    publicClient,
  );

  const call = await makeBuy({
    erc20z,
    poolBalance,
    amount,
    quantity,
    account,
    recipient,
    chainId,
    slippage,
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
  chainId,
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
  chainId: number;
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

export async function sellWithSlippage({
  contract,
  tokenId,
  publicClient,
  quantity,
  chainId,
  account,
  slippage = UNISWAP_SLIPPAGE,
  recipient,
}: SellWithSlippageInput & {
  chainId: number;
  publicClient: PublicClient;
}): Promise<BuyOrSellWithSlippageResult> {
  const secondaryInfo = await getSecondaryInfo({
    contract,
    tokenId,
    publicClient,
    chainId,
  });

  if (!secondaryInfo) {
    return makeError(ERROR_SECONDARY_NOT_CONFIGURED);
  }

  const { pool, secondaryActivated, erc20z } = secondaryInfo;

  if (!secondaryActivated) {
    return makeError(ERROR_SECONDARY_NOT_STARTED);
  }

  const { poolBalance, amount, price } = await getUniswapQuote(
    { type: "sell", quantity, poolAddress: pool, chainId, erc20z },
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
    chainId,
    slippage,
    publicClient,
  });

  return {
    ...call,
    price,
  };
}

/**
 * A client for handling secondary market operations.
 */
export class SecondaryClient {
  private publicClient: PublicClient;
  private chainId: number;

  /**
   * Creates a new SecondaryClient instance.
   * @param publicClient - The public client for interacting with the blockchain.
   * @param chainId - The ID of the blockchain network.
   */
  constructor({
    publicClient,
    chainId,
  }: {
    publicClient: PublicClient;
    chainId: number;
  }) {
    this.publicClient = publicClient;
    this.chainId = chainId;
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
      chainId: this.chainId,
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
    return buyWithSlippage({
      ...input,
      publicClient: this.publicClient,
      chainId: this.chainId,
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
    return sellWithSlippage({
      ...input,
      publicClient: this.publicClient,
      chainId: this.chainId,
    });
  }
}
