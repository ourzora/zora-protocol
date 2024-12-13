import { Address, PublicClient } from "viem";
import { WowERC20ABI } from "../abi/WowERC20";
import { getUniswapQuote } from "./getUniswapQuote";
import { MAX_SUPPLY_BEFORE_GRADUATION } from "../constants";
import { ChainId } from "../types";
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

/// BUY
export async function getBuyQuote({
  chainId,
  tokenAddress,
  amount,
  poolAddress,
  marketType,
  publicClient,
}: {
  chainId: ChainId;
  publicClient: PublicClient;
  tokenAddress: Address;
  amount: bigint;
  poolAddress: Address;
  marketType: MarketType;
}) {
  let quote = 0n;
  if (marketType === MarketType.GRADUATED) {
    const data = await getUniswapQuote({
      chainId,
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
  return quote > MAX_SUPPLY_BEFORE_GRADUATION
    ? MAX_SUPPLY_BEFORE_GRADUATION
    : quote;
}

export async function getSellQuote({
  chainId,
  publicClient,
  tokenAddress,
  amount,
  poolAddress,
  marketType,
}: {
  chainId: ChainId;
  publicClient: PublicClient;
  tokenAddress: Address;
  amount: bigint;
  poolAddress: Address;
  marketType: MarketType;
}) {
  let quote = 0n;
  if (marketType === MarketType.GRADUATED) {
    const data = await getUniswapQuote({
      chainId,
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
  return quote > MAX_SUPPLY_BEFORE_GRADUATION
    ? MAX_SUPPLY_BEFORE_GRADUATION
    : quote;
}
