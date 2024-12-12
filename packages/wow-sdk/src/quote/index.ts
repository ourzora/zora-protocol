import { Address, PublicClient } from "viem";
import { WowERC20ABI } from "../abi/WowERC20";
import { getUniswapQuote } from "./getUniswapQuote";
import { MAX_SUPPLY_BEFORE_GRADUATION } from "../constants";
import { ChainId } from "../types";
import { MarketType } from "../marketType";

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
