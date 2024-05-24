import { parseAbi } from "viem";

export const ZORA_API_BASE = "https://api.zora.co/";
export const OPEN_EDITION_MINT_SIZE = BigInt("18446744073709551615");

// Subgraph base settings
const SUBGRAPH_CONFIG_BASE =
  "https://api.goldsky.com/api/public/project_clhk16b61ay9t49vm6ntn4mkz/subgraphs";

export function getSubgraph(name: string, version: string): string {
  return `${SUBGRAPH_CONFIG_BASE}/${name}/${version}/gn`;
}

export const zora721Abi = parseAbi([
  "function mintWithRewards(address recipient, uint256 quantity, string calldata comment, address mintReferral) external payable",
  "function zoraFeeForAmount(uint256 amount) public view returns (address, uint256)",
] as const);

export const NFT_SALE_QUERY = `
fragment SaleStrategy on SalesStrategyConfig {
  type
  fixedPrice {
    address
    pricePerToken
    saleEnd
    saleStart
    maxTokensPerAddress
  }
  erc20Minter {
    address
    pricePerToken
    currency
    saleEnd
    saleStart
    maxTokensPerAddress
  }
}

query ($id: ID!) {
  zoraCreateToken(id: $id) {
    id
    contract {
      mintFeePerQuantity
      salesStrategies(where: {type_in: ["FIXED_PRICE", "ERC_20_MINTER"]}) {
        ...SaleStrategy
      }
    }
    salesStrategies(where: {type_in: ["FIXED_PRICE", "ERC_20_MINTER"]}) {
      ...SaleStrategy
    }
  }
}
`;
