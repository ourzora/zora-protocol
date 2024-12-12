import { WowERC20ABI } from "./abi/WowERC20";
import { Address, PublicClient } from "viem";

export enum MarketType {
  BONDING = 0,
  GRADUATED = 1,
}

export const getMarketType = async ({
  tokenAddress,
  publicClient,
}: {
  tokenAddress: Address;
  publicClient: PublicClient;
}) => {
  const marketType = await publicClient.readContract({
    address: tokenAddress,
    abi: WowERC20ABI,
    functionName: "marketType",
  });

  return marketType as MarketType;
};
