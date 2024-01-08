import {
  base,
  baseGoerli,
  foundry,
  goerli,
  mainnet,
  optimism,
  optimismGoerli,
  zora,
  zoraSepolia,
  zoraTestnet,
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
  [goerli.id]: {
    chainId: goerli.id,
    isTestnet: true,
    zoraCollectPathChainName: "gor",
    zoraBackendChainName: "ETHEREUM-GOERLI",
    subgraphUrl: getSubgraph("zora-create-goerli", "stable"),
  },
  [zora.id]: {
    chainId: zora.id,
    isTestnet: false,
    zoraCollectPathChainName: "zora",
    zoraBackendChainName: "ZORA-MAINNET",
    subgraphUrl: getSubgraph("zora-create-zora-mainnet", "stable"),
  },
  [zoraTestnet.id]: {
    chainId: zoraTestnet.id,
    isTestnet: true,
    zoraCollectPathChainName: "zgor",
    zoraBackendChainName: "ZORA-GOERLI",
    subgraphUrl: getSubgraph("zora-create-zora-testnet", "stable"),
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
    zoraCollectPathChainName: "opt",
    zoraBackendChainName: "OPTIMISM-MAINNET",
    subgraphUrl: getSubgraph("zora-create-optimism", "stable"),
  },
  [optimismGoerli.id]: {
    chainId: optimismGoerli.id,
    isTestnet: true,
    zoraCollectPathChainName: "ogor",
    zoraBackendChainName: "OPTIMISM-GOERLI",
    subgraphUrl: getSubgraph("zora-create-optimism-goerli", "stable"),
  },
  [base.id]: {
    chainId: base.id,
    isTestnet: false,
    zoraCollectPathChainName: "base",
    zoraBackendChainName: "BASE-MAINNET",
    subgraphUrl: getSubgraph("zora-create-base-mainnet", "stable"),
  },
  [baseGoerli.id]: {
    chainId: baseGoerli.id,
    isTestnet: true,
    zoraCollectPathChainName: "bgor",
    zoraBackendChainName: "BASE-GOERLI",
    subgraphUrl: getSubgraph("zora-create-base-goerli", "stable"),
  },
  [foundry.id]: {
    chainId: foundry.id,
    isTestnet: true,
    zoraCollectPathChainName: "zgor",
    zoraBackendChainName: "ZORA-GOERLI",
    subgraphUrl: getSubgraph("zora-create-zora-testnet", "stable"),
  },
};
