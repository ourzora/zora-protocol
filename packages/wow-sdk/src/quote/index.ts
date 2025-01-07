import { Address, PublicClient, Transport } from "viem";
import { WowERC20ABI } from "../abi/WowERC20";
import { getUniswapQuote } from "./getUniswapQuote";
import { SupportedChain } from "../types";
import { MarketType } from "../marketType";
import { ONE_HUNDRED_PERCENT_BPS, TX_FEE_BPS } from "../constants";

/**
 * Calculate the quote taking into account the 1% transaction fee
 */
export const calculateQuoteWithFees = (quote: bigint) =>
  (quote * (ONE_HUNDRED_PERCENT_BPS - TX_FEE_BPS)) / ONE_HUNDRED_PERCENT_BPS;

// Fee percentage is in basis points (1/100th of a percent)
export const calculateSlippage = (quote: bigint, feePercentage: bigint) =>
  (quote * (ONE_HUNDRED_PERCENT_BPS - feePercentage)) / ONE_HUNDRED_PERCENT_BPS;

/**
 * Checks if the difference between two quotes exceeds the allowed slippage
 * @param originalQuote The original quote amount
 * @param newQuote The new quote amount
 * @param slippageBps The allowed slippage in basis points (e.g., 100 = 1%)
 * @returns true if slippage is exceeded, false otherwise
 */
export function isQuoteChangeExceedingSlippage(
  originalQuote: bigint,
  newQuote: bigint,
  slippageBps: bigint,
): boolean {
  if (originalQuote === 0n) {
    return false;
  }

  // Calculate the ratio of change
  const quoteDiff =
    ((newQuote - originalQuote) * ONE_HUNDRED_PERCENT_BPS) / originalQuote;

  // Return true if the quote difference is less than the slippage
  // We are ok with positive slippage
  return quoteDiff < slippageBps * -1n;
}

/**
 * Get a buy quote for a given market type
 * @param chainId - Chain ID
 * @param tokenAddress - Token address
 * @param amount - Amount of eth
 * @param poolAddress - Pool address
 * @param marketType - Market type
 * @param publicClient - Viem public client
 * @returns Quote
 */
export async function getBuyQuote({
  tokenAddress,
  amount,
  poolAddress,
  marketType,
  publicClient,
}: {
  publicClient: PublicClient<Transport, SupportedChain>;
  tokenAddress: Address;
  amount: bigint;
  poolAddress: Address;
  marketType: MarketType;
}) {
  let quote = 0n;
  if (marketType === MarketType.GRADUATED) {
    const data = await getUniswapQuote({
      poolAddress,
      amount,
      type: "buy",
      publicClient,
    });
    return data.amountOut;
  } else {
    quote = await publicClient.readContract({
      address: tokenAddress,
      abi: WowERC20ABI,
      functionName: "getEthBuyQuote",
      args: [amount],
    });
  }
  return quote;
}

/**
 * Get a sell quote for a given market type
 * @param chainId - Chain ID
 * @param tokenAddress - Token address
 * @param amount - Amount of tokens
 * @param poolAddress - Pool address
 * @param marketType - Market type
 * @param publicClient - Viem public client
 * @returns Quote
 */
export async function getSellQuote({
  publicClient,
  tokenAddress,
  amount,
  poolAddress,
  marketType,
}: {
  publicClient: PublicClient<Transport, SupportedChain>;
  tokenAddress: Address;
  amount: bigint;
  poolAddress: Address;
  marketType: MarketType;
}) {
  let quote = 0n;
  if (marketType === MarketType.GRADUATED) {
    const data = await getUniswapQuote({
      poolAddress,
      amount,
      type: "sell",
      publicClient,
    });
    return data.amountOut;
  } else {
    quote = await publicClient.readContract({
      address: tokenAddress,
      abi: WowERC20ABI,
      functionName: "getTokenSellQuote",
      args: [amount],
    });
  }
  return quote;
}
