import { base, baseSepolia, Chain } from "viem/chains";

export function getChainFromId(chainId: number): Chain {
  if (chainId === base.id) {
    return base;
  }
  if (chainId === baseSepolia.id) {
    return baseSepolia;
  }

  throw new Error(`Chain ID ${chainId} not supported`);
}
