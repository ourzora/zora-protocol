export const ZORA_API_BASE = "https://api.zora.co/";
export const OPEN_EDITION_MINT_SIZE = BigInt("18446744073709551615");

// Subgraph base settings
const CONFIG_BASE =
  "https://api.goldsky.com/api/public/project_clhk16b61ay9t49vm6ntn4mkz/subgraphs";

function getSubgraph(name: string, version: string): string {
  return `${CONFIG_BASE}/${name}/${version}/gn`;
}

export const ZORA_SUBGRAPH_URLS: Record<number, string> = {
  [1]: getSubgraph("zora-create-mainnet", "stable"),
  [5]: getSubgraph("zora-create-goerli", "stable"),
  [10]: getSubgraph("zora-create-optimism", "stable"),
  [420]: getSubgraph("zora-create-optimism-goerli", "stable"),
  [424]: getSubgraph("zora-create-publicgoods", "stable"),
  [999]: getSubgraph("zora-create-zora-testnet", "stable"),
  [7777777]: getSubgraph("zora-create-zora-mainnet", "stable"),
  [84531]: getSubgraph("zora-create-base-goerli", "stable"),
  [8453]: getSubgraph("zora-create-base-mainnet", "stable"),
};
