import { Address, erc20Abi } from "viem";
import { PublicClient as PublicClientWithMulticall } from "viem";
import { PublicClient } from "src/utils";
import { getEthPriceInUSDC } from "./uniswapReserves";
import { convertWeiToSparks, convertWeiToUSD } from "../conversions";

import { uniswapV3PoolAbi } from "./abis";
import { wethAddress as wethAddresses } from "@zoralabs/protocol-deployments";

import { GetQuoteOutput } from "../types";
import {
  quoteExactInputSingle,
  quoteExactOutputSingle,
} from "./uniswapQuoteExact";
import { multicall3Address } from "src/apis/multicall3";

async function getPoolInfo({
  poolAddress,
  client,
  WETH,
  erc20z,
}: {
  poolAddress: Address;
  WETH: Address;
  erc20z: Address;
  client: PublicClient;
}) {
  const [fee, wethBalance, erc20zBalance] = await (
    client as PublicClientWithMulticall
  ).multicall({
    contracts: [
      {
        abi: uniswapV3PoolAbi,
        address: poolAddress,
        functionName: "fee",
      },
      // get WETH and erc20z balance for pool
      {
        abi: erc20Abi,
        address: WETH,
        functionName: "balanceOf",
        args: [poolAddress],
      },
      {
        abi: erc20Abi,
        address: erc20z,
        functionName: "balanceOf",
        args: [poolAddress],
      },
    ],
    multicallAddress: multicall3Address,
    allowFailure: false,
  });

  return {
    wethBalance,
    erc20zBalance,
    fee,
  };
}

type GetQuoteInput = {
  // Indicates whether the quote is for buying or selling
  type: "buy" | "sell";
  // The amount of tokens to buy or sell
  quantity: bigint;
  poolAddress: Address;
  erc20z: Address;
};
export async function getUniswapQuote(
  input: GetQuoteInput,
  client: PublicClient,
): Promise<GetQuoteOutput> {
  const { type, quantity, poolAddress, erc20z } = input;

  const chainId = client.chain.id;

  const WETH = wethAddresses[chainId as keyof typeof wethAddresses];

  const pool = await getPoolInfo({ poolAddress, WETH, erc20z, client });

  const { fee, wethBalance, erc20zBalance } = pool;

  // 1 unit always comes to 1e18 erc20 equivalent
  const amountWithDecimals = input.quantity * 10n ** 18n;

  const amount =
    type === "buy"
      ? await quoteExactOutputSingle({
          tokenIn: WETH,
          tokenOut: erc20z,
          amountOut: amountWithDecimals,
          fee,
          chainId,
          client,
        })
      : await quoteExactInputSingle({
          tokenIn: erc20z,
          tokenOut: WETH,
          amountIn: amountWithDecimals,
          fee,
          chainId,
          client,
        });

  const price = amount;
  const pricePerToken = amount / BigInt(quantity);

  const getUsdPrice = async () => {
    const ethPriceInUSD = await getEthPriceInUSDC();
    return {
      perToken: convertWeiToUSD({ amount: pricePerToken, ethPriceInUSD }),
      total: convertWeiToUSD({ amount: price, ethPriceInUSD }),
    };
  };

  return {
    amount,
    poolBalance: {
      erc20z: erc20zBalance,
      weth: wethBalance,
    },
    price: {
      wei: {
        perToken: pricePerToken,
        total: price,
      },
      sparks: {
        perToken: convertWeiToSparks(pricePerToken),
        total: convertWeiToSparks(price),
      },
      usdc: getUsdPrice,
    },
  };
}
