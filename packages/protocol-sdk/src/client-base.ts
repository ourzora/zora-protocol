import { foundry, zora, zoraTestnet } from "viem/chains";
import type { BackendChainNames as BackendChainNamesType } from "./premint-api-client";
import {
  Chain,
  PublicClient,
  createPublicClient,
  http,
  parseEther,
} from "viem";

export type NetworkConfig = {
  chainId: number;
  zoraPathChainName: string;
  zoraBackendChainName: BackendChainNamesType;
  isTestnet: boolean;
};

export const REWARD_PER_TOKEN = parseEther("0.000777");

export const BackendChainNamesLookup = {
  ZORA_MAINNET: "ZORA-MAINNET",
  ZORA_GOERLI: "ZORA-GOERLI",
} as const;

export const networkConfigByChain: Record<number, NetworkConfig> = {
  [zora.id]: {
    chainId: zora.id,
    isTestnet: false,
    zoraPathChainName: "zora",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_MAINNET,
  },
  [zoraTestnet.id]: {
    chainId: zora.id,
    isTestnet: true,
    zoraPathChainName: "zgor",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_GOERLI,
  },
  [foundry.id]: {
    chainId: foundry.id,
    isTestnet: true,
    zoraPathChainName: "zgor",
    zoraBackendChainName: BackendChainNamesLookup.ZORA_GOERLI,
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
