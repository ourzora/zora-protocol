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
import { getSubgraph } from "../constants";

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
    subgraphUrl: getSubgraph("zora-create-mainnet", "stable"),
  },
  [sepolia.id]: {
    chainId: sepolia.id,
    isTestnet: true,
    zoraCollectPathChainName: "sep",
    zoraBackendChainName: "ETHEREUM-SEPOLIA",
    subgraphUrl: getSubgraph("zora-create-sepolia", "stable"),
  },
  [zora.id]: {
    chainId: zora.id,
    isTestnet: false,
    zoraCollectPathChainName: "zora",
    zoraBackendChainName: "ZORA-MAINNET",
    subgraphUrl: getSubgraph("zora-create-zora-mainnet", "stable"),
  },
  [zoraSepolia.id]: {
    chainId: zoraSepolia.id,
    isTestnet: true,
    zoraCollectPathChainName: "zsep",
    zoraBackendChainName: "ZORA-SEPOLIA",
    subgraphUrl: getSubgraph("zora-create-zora-sepolia", "stable"),
  },
  [optimism.id]: {
    chainId: optimism.id,
    isTestnet: false,
    zoraCollectPathChainName: "oeth",
    zoraBackendChainName: "OPTIMISM-MAINNET",
    subgraphUrl: getSubgraph("zora-create-optimism", "stable"),
  },
  [arbitrum.id]: {
    chainId: arbitrum.id,
    isTestnet: true,
    zoraCollectPathChainName: "arb",
    zoraBackendChainName: "ARBITRUM-MAINNET",
    subgraphUrl: getSubgraph("zora-create-arbitrum-one", "stable"),
  },
  [base.id]: {
    chainId: base.id,
    isTestnet: false,
    zoraCollectPathChainName: "base",
    zoraBackendChainName: "BASE-MAINNET",
    subgraphUrl: getSubgraph("zora-create-base-mainnet", "stable"),
  },
  [baseSepolia.id]: {
    chainId: baseSepolia.id,
    isTestnet: true,
    zoraCollectPathChainName: "bsep",
    zoraBackendChainName: "BASE-SEPOLIA",
    subgraphUrl: getSubgraph("zora-create-base-sepolia", "stable"),
  },
  [foundry.id]: {
    chainId: foundry.id,
    isTestnet: true,
    zoraCollectPathChainName: "zgor",
    zoraBackendChainName: "ZORA-GOERLI",
    subgraphUrl: getSubgraph("zora-create-zora-testnet", "stable"),
  },
};

export const getSubgraphUrl = (chainId: number): string => {
  const networkConfig = networkConfigByChain[chainId];

  if (!networkConfig) {
    throw new Error(`Network not configured for chain id ${chainId}`);
  }

  return networkConfig.subgraphUrl;
};
