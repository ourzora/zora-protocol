import type { Address } from "viem";

/** Base chain ID */
export const BASE_CHAIN_ID = 8453;

/** Well-known token addresses on Base */
export const WETH_ADDRESS: Address =
  "0x4200000000000000000000000000000000000006";
export const USDC_ADDRESS: Address =
  "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
export const ZORA_ADDRESS: Address =
  "0x1111111111166b7FE7bd91427724B487980aFc69";

/** USDC uses 6 decimals */
export const USDC_DECIMALS = 6;

/** Token configuration for buy/sell commands */
export const BASE_TRADE_TOKENS = {
  eth: {
    symbol: "ETH",
    decimals: 18,
    trade: { type: "eth" as const },
    priceAddress: WETH_ADDRESS,
    fixedPriceUsd: undefined as number | undefined,
  },
  usdc: {
    symbol: "USDC",
    decimals: USDC_DECIMALS,
    trade: {
      type: "erc20" as const,
      address: USDC_ADDRESS,
    },
    priceAddress: USDC_ADDRESS,
    fixedPriceUsd: 1,
  },
  zora: {
    symbol: "ZORA",
    decimals: 18,
    trade: {
      type: "erc20" as const,
      address: ZORA_ADDRESS,
    },
    priceAddress: ZORA_ADDRESS,
    fixedPriceUsd: undefined as number | undefined,
  },
} as const;

export type TradeTokenKey = keyof typeof BASE_TRADE_TOKENS;
