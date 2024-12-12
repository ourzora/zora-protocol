import { Address, getContract, PublicClient } from "viem";

import UniswapV3PoolABI from "../abi/UniswapV3Pool";
import { WowERC20ABI } from "../abi/WowERC20";

export interface PoolInfo {
  token0: Address;
  balance0: bigint;
  token1: Address;
  balance1: bigint;
  fee: number;
  liquidity: bigint;
  sqrtPriceX96: bigint;
}

export async function getPoolInfo(
  poolAddress: Address,
  publicClient: PublicClient,
): Promise<PoolInfo> {
  try {
    const contract = getContract({
      address: poolAddress,
      abi: UniswapV3PoolABI,
      client: publicClient,
    });

    const [token0, token1, fee, liquidity, slot0] = await Promise.all([
      contract.read.token0(),
      contract.read.token1(),
      contract.read.fee(),
      contract.read.liquidity(),
      contract.read.slot0(),
    ]);

    const [balance0, balance1] = await Promise.all([
      publicClient.readContract({
        abi: WowERC20ABI,
        address: token0,
        functionName: "balanceOf",
        args: [poolAddress],
      }),
      publicClient.readContract({
        abi: WowERC20ABI,
        address: token1,
        functionName: "balanceOf",
        args: [poolAddress],
      }),
    ]);

    return {
      token0,
      balance0,
      token1,
      balance1,
      fee,
      liquidity,
      sqrtPriceX96: slot0[0],
    };
  } catch (error) {
    throw new Error("Failed to fetch pool information", { cause: error });
  }
}
