import {
  Address,
  getContract,
  isAddressEqual,
  PublicClient,
  Transport,
} from "viem";
import { base, baseSepolia, mainnet } from "viem/chains";
import UniswapQuoterABI from "../abi/UniswapQuoter";
import WETHABI from "../abi/WETH";
import { PoolInfo } from "./getPoolInfo";
import { ChainId, SupportedChain } from "../types";
import { addresses } from "../addresses";
import { getPoolInfo } from "./getPoolInfo";

const WETH = {
  abi: WETHABI,
  address: {
    [base.id]: addresses[base.id].WETH as Address,
    [baseSepolia.id]: addresses[baseSepolia.id].WETH as Address,
    [mainnet.id]: addresses[mainnet.id].WETH as Address,
  },
};

const UniswapQuoter = {
  abi: UniswapQuoterABI,
  address: {
    [base.id]: addresses[base.id].UniswapQuoter as Address,
    [baseSepolia.id]: addresses[baseSepolia.id].UniswapQuoter as Address,
    [mainnet.id]: addresses[mainnet.id].UniswapQuoter as Address,
  },
};

interface PriceInfo {
  wei: bigint;
  usd: string;
}

export interface Quote {
  amount: bigint;
  balance?: {
    erc20z: bigint;
    weth: bigint;
  };
  price?: {
    perToken: PriceInfo;
    total: PriceInfo;
  };
  fee?: number;
  error?: string;
}

async function exactInputSingle(
  tokenIn: Address,
  tokenOut: Address,
  amountIn: bigint,
  fee: number,
  chainId: ChainId,
  publicClient: PublicClient<Transport, SupportedChain>,
): Promise<Omit<Quote, "price" | "balance" | "fee">> {
  const contract = getContract({
    address: UniswapQuoter.address[chainId],
    abi: UniswapQuoter.abi,
    client: publicClient,
  });

  const quote = await contract.simulate.quoteExactInputSingle([
    {
      tokenIn,
      tokenOut,
      amountIn: amountIn,
      fee,
      sqrtPriceLimitX96: 0n,
    },
  ]);

  const amountOut = quote.result[0];

  return {
    amount: amountOut,
  };
}

/**
 * Get a quote for a given pool address, used for tokens that have graduated to uniswap
 * @param chainId - Chain ID
 * @param poolAddress - Pool address - if not passed in, will fetch from the contract
 * @param amount - Amount of eth if buy, tokens if sell
 * @param type - Type of quote, buy or sell
 * @param publicClient - Viem public client
 * @returns Quote
 */
export async function getUniswapQuote({
  poolAddress,
  amount,
  type,
  publicClient,
}: {
  poolAddress: Address;
  amount: bigint;
  type: "buy" | "sell";
  publicClient: PublicClient<Transport, SupportedChain>;
}) {
  let pool: PoolInfo | undefined;
  let tokens: [`0x${string}`, `0x${string}`] | undefined;
  let balances: [bigint, bigint] | undefined;
  let quote: Omit<Quote, "price" | "balance" | "fee"> | undefined;
  let utilization = 0n;
  let insufficientLiquidity = false;
  const chainId = publicClient.chain?.id;

  let fetchingError: Error | undefined;

  try {
    const poolInfo = await getPoolInfo(poolAddress, publicClient);

    const { token0, token1, balance0, balance1, fee } = poolInfo;

    pool = poolInfo;
    tokens = [token0, token1];
    balances = [balance0, balance1];

    const isToken0Weth = isAddressEqual(token0, WETH.address[chainId]);
    const tokenIn =
      type === "buy"
        ? isToken0Weth
          ? token0
          : token1
        : isToken0Weth
          ? token1
          : token0;

    const [tokenOut, balanceOut] =
      tokenIn === token0 ? [token1, balance1] : [token0, balance0];

    insufficientLiquidity = type === "buy" && amount > balanceOut;
    utilization = type === "buy" ? amount / balanceOut : utilization;

    quote = await exactInputSingle(
      tokenIn,
      tokenOut,
      amount,
      fee,
      chainId,
      publicClient,
    );
  } catch (error: any) {
    if (error?.message?.includes("The address is not a contract.")) {
      fetchingError = new Error("Failed fetching pool");
    } else {
      fetchingError = error;
    }
  }

  insufficientLiquidity =
    (type === "sell" && !!pool && !quote) || insufficientLiquidity;

  const error = !pool
    ? new Error("Failed fetching pool")
    : insufficientLiquidity
      ? new Error("Insufficient liquidity")
      : !quote && utilization >= 0.9
        ? new Error("Price impact too high")
        : !quote
          ? new Error("Failed fetching quote")
          : undefined;

  return {
    amountIn: amount,
    amountOut: quote?.amount ?? 0n,
    balance:
      !!tokens && !!balances
        ? {
            erc20z: isAddressEqual(tokens[0], WETH.address[chainId])
              ? balances[1]
              : balances[0],
            weth: isAddressEqual(tokens[0], WETH.address[chainId])
              ? balances[0]
              : balances[1],
          }
        : undefined,

    // uniswap pool fee is scaled by 1000000 (1e6)
    fee: !!pool ? pool.fee / 1000000 : undefined,
    error: fetchingError || error,
  };
}
