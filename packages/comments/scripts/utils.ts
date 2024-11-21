import {
  createPublicClient,
  http,
  Chain,
  createWalletClient,
  PublicClient,
  WalletClient,
  Transport,
} from "viem";
import * as chains from "viem/chains";
import { getChain } from "@zoralabs/chains";

export const makeClientsForChain = async (
  chainName: string,
): Promise<{
  publicClient: PublicClient;
  walletClient: WalletClient<Transport, Chain>;
  chainId: number;
}> => {
  const configuredChain = await getChain(chainName);

  if (configuredChain.id === 9999999) {
    configuredChain.id = chains.zoraSepolia.id;
  }

  if (!configuredChain) {
    throw new Error(`No chain config found for chain name ${chainName}`);
  }

  const chainConfig = Object.values(chains).find(
    (x) => x.id === configuredChain.id,
  );

  if (!chainConfig) {
    throw new Error(`No chain config found for chain id ${configuredChain.id}`);
  }

  const rpcUrl = configuredChain.rpcUrl;

  if (!rpcUrl) {
    throw new Error(`No RPC found for chain id ${configuredChain.id}`);
  }

  return {
    publicClient: createPublicClient({
      transport: http(),
      chain: {
        ...chainConfig,
        rpcUrls: {
          default: {
            http: [rpcUrl],
          },
          public: {
            http: [rpcUrl],
          },
        },
      },
    }) as PublicClient,
    walletClient: createWalletClient({
      transport: http(),
      chain: {
        ...chainConfig,
        rpcUrls: {
          default: {
            http: [rpcUrl],
          },
          public: {
            http: [rpcUrl],
          },
        },
      },
    }),
    chainId: configuredChain.id as number,
  };
};

export const makeWalletClientForChain = async (chainName: string) => {
  const configuredChain = await getChain(chainName);

  if (configuredChain.id === 9999999) {
    configuredChain.id = chains.zoraSepolia.id;
  }
};
export function getChainNamePositionalArg() {
  // parse chain id as first argument:
  const chainName = process.argv[2];

  if (!chainName) {
    throw new Error("Must provide chain name as first argument");
  }

  return chainName;
}

const CONFIG_BASE =
  "https://api.goldsky.com/api/public/project_clhk16b61ay9t49vm6ntn4mkz/subgraphs";

export function getSubgraph(name: string, version: string = "stable"): string {
  return `${CONFIG_BASE}/${name}/${version}/gn`;
}

const subgraphChainName = (chainName: string) => {
  if (chainName === "zora") {
    return "zora-mainnet";
  }
  if (chainName === "base") {
    return "base-mainnet";
  }

  return chainName;
};

export async function getChainConfig(chainName: string) {
  const subgraph = getSubgraph(
    `zora-create-${subgraphChainName(chainName)}`,
    "stable",
  );
  const { publicClient, walletClient, chainId } =
    await makeClientsForChain(chainName);

  return {
    publicClient: publicClient as PublicClient<Transport, Chain>,
    walletClient: walletClient as WalletClient<Transport, Chain>,
    chainId,
    subgraph,
  };
}
