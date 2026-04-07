import { formatEther } from "viem";

export const WEI_PER_SPARK = 1_000_000_000_000n;

export function convertWeiToSparks(wei: string | number | bigint) {
  return BigInt(wei) / WEI_PER_SPARK;
}

// Returns the price in USDC given an amount in WEI
export function convertWeiToUSD({
  amount,
  ethPriceInUSD,
}: {
  amount: bigint;
  ethPriceInUSD: number;
}) {
  const amountInEth = formatEther(amount);

  return parseFloat(amountInEth) * ethPriceInUSD;
}
