import { Address } from "viem";
import {
  mainnet,
  sepolia,
  zora,
  zoraSepolia,
  base,
  baseSepolia,
  optimism,
  arbitrum,
  blast,
} from "viem/chains";
import { uniswapQuoterABI } from "./abis";
import { PublicClient } from "../../utils";

const UniswapQuoterAddress: Record<number, Address> = {
  [mainnet.id]: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
  [sepolia.id]: "0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3",
  [zora.id]: "0x11867e1b3348F3ce4FcC170BC5af3d23E07E64Df",
  [zoraSepolia.id]: "0xC195976fEF0985886E37036E2DF62bF371E12Df0",
  [base.id]: "0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a",
  [baseSepolia.id]: "0xC5290058841028F1614F3A6F0F5816cAd0df5E27",
  [optimism.id]: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
  [arbitrum.id]: "0x61fFE014bA17989E743c5F6cB21bF9697530B21e",
  [blast.id]: "0x6Cdcd65e03c1CEc3730AeeCd45bc140D57A25C77",
};

/**
 * Fetches a quote for buying an exact amount of erc20z from the uniswap pool
 *
 * @param tokenIn - the token to sell (will be weth)
 * @param tokenOut - the token to purchase (will be an erc20z)
 * @param amount - the exact amount of erc20z to purchase
 * @param fee - the fee of the pool
 * @param chainId - the chain id
 */
export async function quoteExactOutputSingle({
  tokenIn,
  tokenOut,
  amountOut,
  fee,
  chainId,
  client,
}: {
  tokenIn: Address;
  tokenOut: Address;
  amountOut: bigint;
  fee: number;
  chainId: number;
  client: PublicClient;
}): Promise<bigint> {
  const quote = await client.simulateContract({
    abi: uniswapQuoterABI,
    address: UniswapQuoterAddress[
      chainId as keyof typeof UniswapQuoterAddress
    ] as Address,
    functionName: "quoteExactOutputSingle",
    args: [
      {
        tokenIn,
        tokenOut,
        amount: amountOut,
        fee,
        sqrtPriceLimitX96: 0n,
      },
    ],
  });

  return quote.result[0];
}

/**
 * Fetches a quote for selling an exact amount of erc20z to the uniswap pool
 *
 * @param tokenIn - the token to sell (will be erc20z)
 * @param tokenOut - the token to purchase (will be weth)
 * @param amount - the exact amount of erc20z to sell
 * @param fee - the fee of the pool
 * @param chainId - the chain id
 */
export async function quoteExactInputSingle({
  tokenIn,
  tokenOut,
  amountIn,
  fee,
  chainId,
  client,
}: {
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  fee: number;
  chainId: number;
  client: PublicClient;
}): Promise<bigint> {
  const quote = await client.simulateContract({
    abi: uniswapQuoterABI,
    address: UniswapQuoterAddress[
      chainId as keyof typeof UniswapQuoterAddress
    ] as Address,
    functionName: "quoteExactInputSingle",
    args: [
      {
        tokenIn,
        tokenOut,
        amountIn,
        fee,
        sqrtPriceLimitX96: 0n,
      },
    ],
  });

  return quote.result[0];
}
