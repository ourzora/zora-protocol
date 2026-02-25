import {
  arbitrum,
  base,
  baseSepolia,
  foundry,
  mainnet,
  optimism,
  sepolia,
  zora,
  zoraSepolia,
} from "viem/chains";
import type { components } from "./generated/premint-api-types";
import { parseEther } from "viem";
type BackendChainName = components["schemas"]["ChainName"];

export type NetworkConfig = {
  chainId: number;
  zoraCollectPathChainName: string;
  zoraBackendChainName: BackendChainName;
  isTestnet: boolean;
  subgraphUrl: string;
};

export const REWARD_PER_TOKEN = parseEther("0.000777");

export const networkConfigByChain: Record<number, NetworkConfig> = {
  [mainnet.id]: {
    chainId: mainnet.id,
    isTestnet: false,
    zoraCollectPathChainName: "eth",
    zoraBackendChainName: "ETHEREUM-MAINNET",
    subgraphUrl: "",
  },
  [sepolia.id]: {
    chainId: sepolia.id,
    isTestnet: true,
    zoraCollectPathChainName: "sep",
    zoraBackendChainName: "ETHEREUM-SEPOLIA",
    subgraphUrl: "",
  },
  [zora.id]: {
    chainId: zora.id,
    isTestnet: false,
    zoraCollectPathChainName: "zora",
    zoraBackendChainName: "ZORA-MAINNET",
    subgraphUrl: "",
  },
  [zoraSepolia.id]: {
    chainId: zoraSepolia.id,
    isTestnet: true,
    zoraCollectPathChainName: "zsep",
    zoraBackendChainName: "ZORA-SEPOLIA",
    subgraphUrl: "",
  },
  [optimism.id]: {
    chainId: optimism.id,
    isTestnet: false,
    zoraCollectPathChainName: "oeth",
    zoraBackendChainName: "OPTIMISM-MAINNET",
    subgraphUrl: "",
  },
  [arbitrum.id]: {
    chainId: arbitrum.id,
    isTestnet: true,
    zoraCollectPathChainName: "arb",
    zoraBackendChainName: "ARBITRUM-MAINNET",
    subgraphUrl: "",
  },
  [base.id]: {
    chainId: base.id,
    isTestnet: false,
    zoraCollectPathChainName: "base",
    zoraBackendChainName: "BASE-MAINNET",
    subgraphUrl: "",
  },
  [baseSepolia.id]: {
    chainId: baseSepolia.id,
    isTestnet: true,
    zoraCollectPathChainName: "bsep",
    zoraBackendChainName: "BASE-SEPOLIA",
    subgraphUrl: "",
  },
  [foundry.id]: {
    chainId: foundry.id,
    isTestnet: true,
    zoraCollectPathChainName: "zgor",
    zoraBackendChainName: "ZORA-GOERLI",
    subgraphUrl: "",
  },
};

export const getSubgraphUrl = (chainId: number): string => {
  const networkConfig = networkConfigByChain[chainId];

  if (!networkConfig) {
    throw new Error(`Network not configured for chain id ${chainId}`);
  }

  return networkConfig.subgraphUrl;
};
