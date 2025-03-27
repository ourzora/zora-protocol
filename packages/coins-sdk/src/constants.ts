import { zoraFactoryImplAddress } from "@zoralabs/coins";
import { Address } from "viem";
import { base } from "viem/chains";

// this is the same across all chains due to deterministic deploys.
export const COIN_FACTORY_ADDRESS = zoraFactoryImplAddress["8453"] as Address;

export const SUPERCHAIN_WETH_ADDRESS =
  "0x4200000000000000000000000000000000000006";

export const USDC_WETH_POOLS_BY_CHAIN: Record<number, Address> = {
  [base.id]: "0xd0b53D9277642d899DF5C87A3966A349A798F224",
};
