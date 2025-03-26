import { coinABI, iUniswapV3PoolABI } from "@zoralabs/coins";
import {
  SUPERCHAIN_WETH_ADDRESS,
  USDC_WETH_POOLS_BY_CHAIN,
} from "../constants";
import { GenericPublicClient } from "../utils/genericPublicClient";
import { validateClientNetwork } from "../utils/validateClientNetwork";
import {
  Address,
  erc20Abi,
  formatEther,
  isAddressEqual,
  zeroAddress,
} from "viem";

type Slot0Result = {
  sqrtPriceX96: bigint;
  tick: number;
  observationIndex: number;
  observationCardinality: number;
  observationCardinalityNext: number;
  feeProtocol: number;
  unlocked: boolean;
};

type PricingResult = {
  eth: bigint;
  usdc: bigint | null;
  usdcDecimal: number | null;
  ethDecimal: number;
};

/**
 * Represents the current state of a coin
 * @typedef {Object} OnchainCoinDetails
 * @property {bigint} balance - The user's balance of the coin
 * @property {PricingResult} marketCap - The market cap of the coin
 * @property {PricingResult} liquidity - The liquidity of the coin
 * @property {Address} pool - Pool address
 * @property {Slot0Result} poolState - Current state of the UniswapV3 pool
 * @property {Address[]} owners - List of owners for the coin
 * @property {Address} payoutRecipient - The payout recipient address
 */
export type OnchainCoinDetails = {
  balance: bigint;
  marketCap: PricingResult;
  liquidity: PricingResult;
  pool: Address;
  poolState: Slot0Result;
  owners: readonly Address[];
  payoutRecipient: Address;
};

/**
 * Gets the current state of a coin for a user
 * @param {Object} params - The query parameters
 * @param {Address} params.coin - The coin contract address
 * @param {Address} params.user - The user address to check balance for
 * @param {PublicClient} params.publicClient - The viem public client instance
 * @returns {Promise<OnchainCoinDetails>} The coin's current state
 */
export async function getOnchainCoinDetails({
  coin,
  user = zeroAddress,
  publicClient,
}: {
  coin: Address;
  user?: Address;
  publicClient: GenericPublicClient;
}): Promise<OnchainCoinDetails> {
  validateClientNetwork(publicClient);
  const [balance, pool, owners, payoutRecipient] = await publicClient.multicall(
    {
      contracts: [
        {
          address: coin,
          abi: coinABI,
          functionName: "balanceOf",
          args: [user],
        },
        {
          address: coin,
          abi: coinABI,
          functionName: "poolAddress",
        },
        {
          address: coin,
          abi: coinABI,
          functionName: "owners",
        },
        {
          address: coin,
          abi: coinABI,
          functionName: "payoutRecipient",
        },
      ],
      allowFailure: false,
    },
  );

  const USDC_WETH_POOL = USDC_WETH_POOLS_BY_CHAIN[publicClient.chain?.id || 0];

  const [
    coinWethPoolSlot0,
    coinWethPoolToken0,
    coinReservesRaw,
    coinTotalSupply,
    wethReservesRaw,
    usdcWethSlot0,
  ] = await publicClient.multicall({
    contracts: [
      {
        address: pool,
        abi: iUniswapV3PoolABI,
        functionName: "slot0",
      },
      {
        address: pool,
        abi: iUniswapV3PoolABI,
        functionName: "token0",
      },
      {
        address: coin,
        abi: erc20Abi,
        functionName: "balanceOf",
        args: [pool],
      },
      {
        address: coin,
        abi: coinABI,
        functionName: "totalSupply",
      },
      {
        address: SUPERCHAIN_WETH_ADDRESS,
        abi: erc20Abi,
        functionName: "balanceOf",
        args: [pool],
      },
      {
        address: USDC_WETH_POOL ?? coin,
        abi: iUniswapV3PoolABI,
        functionName: "slot0",
      },
    ],
    allowFailure: false,
  });

  const wethPriceInUsdc = USDC_WETH_POOL
    ? uniswapV3SqrtPriceToBigIntScaled(
        usdcWethSlot0.sqrtPriceX96,
        18,
        6,
        true,
        18,
      )
    : null;

  const coinPriceInWeth = uniswapV3SqrtPriceToBigIntScaled(
    coinWethPoolSlot0.sqrtPriceX96,
    18,
    18,
    isAddressEqual(coinWethPoolToken0, coin),
    18,
  );

  // Divide by 10^18 to remove percision from `coinPriceInWeth` after math since bigint is decimal.
  const marketCap = (coinPriceInWeth * coinTotalSupply) / 10n ** 18n;

  const wethLiquidity = wethReservesRaw;
  // Divide by 10^18 to remove percision from `coinPriceInWeth` after math since bigint is decimal.
  const tokenLiquidity = (coinReservesRaw * coinPriceInWeth) / 10n ** 18n;

  return {
    balance,
    pool,
    owners,
    payoutRecipient,
    marketCap: convertEthOutput(marketCap, wethPriceInUsdc),
    liquidity: convertEthOutput(
      wethLiquidity + tokenLiquidity,
      wethPriceInUsdc,
    ),
    poolState: coinWethPoolSlot0,
  };
}

function convertEthOutput(amountETH: bigint, wethToUsdc: bigint | null) {
  return {
    eth: amountETH,
    ethDecimal: parseFloat(formatEther(amountETH)),
    usdc: wethToUsdc ? amountETH * wethToUsdc : null,
    usdcDecimal: wethToUsdc
      ? parseFloat(formatEther((amountETH * wethToUsdc) / 10n ** 18n))
      : null,
  };
}

function uniswapV3SqrtPriceToBigIntScaled(
  sqrtPriceX96: bigint,
  token0Decimals: number,
  token1Decimals: number,
  isToken0Coin: boolean,
  scaleDecimals: number = 18,
): bigint {
  // (sqrtPrice^2 / 2^192) => ratio
  // We'll do: ratioScaled = (sqrtPrice^2 * 10^scaleDecimals) / 2^192
  const numerator = sqrtPriceX96 * sqrtPriceX96;
  const denominator = 2n ** 192n;
  const scaleFactor = 10n ** BigInt(scaleDecimals);

  // raw ratioScaled
  let ratioScaled = (numerator * scaleFactor) / denominator; // BigInt

  // Adjust for difference in decimals:
  // ratioScaled *= 10^(dec0 - dec1)
  const decimalsDiff = BigInt(token0Decimals - token1Decimals);
  if (decimalsDiff > 0n) {
    ratioScaled *= 10n ** decimalsDiff;
  } else if (decimalsDiff < 0n) {
    ratioScaled /= 10n ** -decimalsDiff;
  }

  if (!isToken0Coin) {
    // We want the reciprocal: coin is token1 => coinPriceInToken0 = 1 / ratio
    // But we also want it scaled by 10^scaleDecimals
    // reciprocalScaled = (10^scaleDecimals * 10^(decimalsDiff)) / ratioScaled
    // (assuming ratioScaled != 0)
    if (ratioScaled === 0n) {
      return 0n; // or some huge number representing infinity
    }
    ratioScaled = (scaleFactor * scaleFactor) / ratioScaled;
    // or if we already included decimalsDiff above, handle carefully.
  }

  return ratioScaled;
}
