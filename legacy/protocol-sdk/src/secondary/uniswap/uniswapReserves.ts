import { createPublicClient, http } from "viem";
import { mainnet } from "viem/chains";
import { uniswapV2USDCAbi } from "./abis";

const uniswapV2USDCMainnetAddress =
  "0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc";

export function getUniswapV2USDCReserves() {
  const mainnetClient = createPublicClient({
    chain: mainnet,
    transport: http(),
  });
  return mainnetClient.readContract({
    address: uniswapV2USDCMainnetAddress,
    abi: uniswapV2USDCAbi,
    functionName: "getReserves",
  });
}

function toEthPriceInUSDC({
  reserve0,
  reserve1,
}: {
  reserve0: bigint;
  reserve1: bigint;
}) {
  return Number((reserve0 * BigInt(1e14)) / reserve1) / 1e2;
}

// returns the ETH price in USDC
export async function getEthPriceInUSDC() {
  const reserves = await getUniswapV2USDCReserves();
  return toEthPriceInUSDC({ reserve0: reserves[0], reserve1: reserves[1] });
}
