import { Chain, PublicClient, createPublicClient, http } from "viem";
import { NetworkConfig, networkConfigByChain } from "./chain-constants";

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
