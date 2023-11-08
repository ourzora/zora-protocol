import {
  base,
  baseGoerli,
  foundry,
  goerli,
  mainnet,
  optimism,
  optimismGoerli,
  zora,
  zoraTestnet,
} from "viem/chains";
import type { components } from "./generated/premint-api-types";
import {
  Chain,
  PublicClient,
  createPublicClient,
  http,
  parseEther,
} from "viem";
import { getSubgraph } from "../constants";

export type NetworkConfig = {
  chainId: number;
  zoraPathChainName: string;
  zoraBackendChainName: components['schemas']['ChainName'];
  isTestnet: boolean;
  subgraphUrl: string;
};

export const REWARD_PER_TOKEN = parseEther("0.000777");

export const BackendChainNamesLookup = {
  ZORA_MAINNET: "ZORA-MAINNET",
  ZORA_GOERLI: "ZORA-GOERLI",
  OPTIMISM_MAINNET: "OPTIMISM-MAINNET",
  OPTIMISM_GOERLI: "OPTIMISM-GOERLI",
  ETHEREUM_MAINNET: "ETHEREUM-MAINNET",
  ETHEREUM_GOERLI: "ETHEREUM-GOERLI",
  BASE_MAINNET: "BASE-MAINNET",
  BASE_GOERLI: "BASE-GOERLI",
} as const;

export const networkConfigByChain: Record<number, NetworkConfig> = {
  [mainnet.id]: {
    chainId: mainnet.id,
    isTestnet: false,
    zoraPathChainName: "eth",
    zoraBackendChainName: BackendChainNamesLookup.ETHEREUM_MAINNET,
    subgraphUrl: getSubgraph("zora-create-mainnet", "stable"),
  },
  [goerli.id]: {
    chainId: goerli.id,
    isTestnet: true,
    zoraPathChainName: "gor",
    zoraBackendChainName: BackendChainNamesLookup.ETHEREUM_GOERLI,
    subgraphUrl: getSubgraph("zora-create-goerli", "stable"),
  },
  [zora.id]: {
    chainId: zora.id,
    isTestnet: false,
    zoraPathChainName: "zora",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_MAINNET,
    subgraphUrl: getSubgraph("zora-create-zora-mainnet", "stable"),
  },
  [zoraTestnet.id]: {
    chainId: zora.id,
    isTestnet: true,
    zoraPathChainName: "zgor",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_GOERLI,
    subgraphUrl: getSubgraph("zora-create-zora-testnet", "stable"),
  },
  [optimism.id]: {
    chainId: optimism.id,
    isTestnet: false,
    zoraPathChainName: "opt",
    zoraBackendChainName: BackendChainNamesLookup.OPTIMISM_MAINNET,
    subgraphUrl: getSubgraph("zora-create-optimism", "stable"),
  },
  [optimismGoerli.id]: {
    chainId: optimismGoerli.id,
    isTestnet: true,
    zoraPathChainName: "ogor",
    zoraBackendChainName: BackendChainNamesLookup.OPTIMISM_GOERLI,
    subgraphUrl: getSubgraph("zora-create-optimism-goerli", "stable"),
  },
  [base.id]: {
    chainId: base.id,
    isTestnet: false,
    zoraPathChainName: "base",
    zoraBackendChainName: BackendChainNamesLookup.BASE_MAINNET,
    subgraphUrl: getSubgraph("zora-create-base-mainnet", "stable"),
  },
  [baseGoerli.id]: {
    chainId: baseGoerli.id,
    isTestnet: true,
    zoraPathChainName: "bgor",
    zoraBackendChainName: BackendChainNamesLookup.BASE_GOERLI,
    subgraphUrl: getSubgraph("zora-create-base-goerli", "stable"),
  },
  [foundry.id]: {
    chainId: foundry.id,
    isTestnet: true,
    zoraPathChainName: "zgor",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_GOERLI,
    subgraphUrl: getSubgraph("zora-create-zora-testnet", "stable"),
  },
};

export abstract class ClientBase {
  network: NetworkConfig;
  chain: Chain;

  constructor(chain: Chain) {
    this.chain = chain;
    const networkConfig = networkConfigByChain[chain.id];
    if (!networkConfig) {
      throw new Error(`Not configured for chain ${chain.id}`);
    }
    this.network = networkConfig;
  }

  /**
   * Getter for public client that instantiates a publicClient as needed
   *
   * @param publicClient Optional viem public client
   * @returns Existing public client or makes a new one for the given chain as needed.
   */
  protected getPublicClient(publicClient?: PublicClient): PublicClient {
    if (publicClient) {
      return publicClient;
    }
    return createPublicClient({ chain: this.chain, transport: http() });
  }
}
