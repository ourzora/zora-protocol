import { ISubgraphQuery } from "src/apis/subgraph-querier";
import { GenericTokenIdTypes } from "src/types";
import { Address } from "viem";

export type FixedPriceSaleStrategyResult = {
  type: "FIXED_PRICE";
  fixedPrice: {
    address: Address;
    pricePerToken: string;
    saleEnd: string;
    saleStart: string;
    maxTokensPerAddress: string;
  };
};

export type ERC20SaleStrategyResult = {
  type: "ERC_20_MINTER";
  erc20Minter: {
    address: Address;
    pricePerToken: string;
    saleEnd: string;
    saleStart: string;
    maxTokensPerAddress: string;
    currency: Address;
  };
};

export type PresaleSalesStrategyResult = {
  type: "PRESALE";
  presale: {
    address: Address;
    presaleStart: string;
    presaleEnd: string;
    merkleRoot: string;
  };
};

export type ZoraTimedMinterSaleStrategyResult = {
  type: "ZORA_TIMED";
  zoraTimedMinter: {
    address: Address;
    mintFee: string;
    saleStart: string;
    saleEnd: string;
    erc20Z: {
      id: Address;
      pool: Address;
    };
    secondaryActivated: boolean;
    marketCountdown?: string;
    minimumMarketEth?: string;
  };
};

export type SalesStrategyResult =
  | FixedPriceSaleStrategyResult
  | ERC20SaleStrategyResult
  | PresaleSalesStrategyResult
  | ZoraTimedMinterSaleStrategyResult;

export type TokenQueryResult = {
  tokenId?: string;
  creator: Address;
  uri: string;
  totalMinted: string;
  maxSupply: string;
  salesStrategies?: SalesStrategyResult[];
  tokenStandard: "ERC1155" | "ERC721";
  contract: {
    mintFeePerQuantity: string;
    salesStrategies: SalesStrategyResult[];
    address: Address;
    contractVersion: string;
    contractURI: string;
    name: string;
  };
};

const NFT_SALE_STRATEGY_FRAGMENT = `
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
  presale {
    address
    presaleStart
    presaleEnd
    merkleRoot
  }
  zoraTimedMinter {
    address
    mintFee
    saleStart
    saleEnd
    erc20Z {
      id 
      pool
    }
    secondaryActivated
    marketCountdown
    minimumMarketEth
  }
}`;

const TOKEN_FRAGMENT = `
fragment Token on ZoraCreateToken {
    creator
    tokenId
    uri
    totalMinted
    maxSupply
    tokenStandard
    salesStrategies(where: {type_in: ["FIXED_PRICE", "ERC_20_MINTER", "PRESALE", "ZORA_TIMED"]}) {
      ...SaleStrategy
    }
    contract {
      address
      mintFeePerQuantity
      contractVersion
      contractURI
      name
      salesStrategies(where: {type_in: ["FIXED_PRICE", "ERC_20_MINTER", "PRESALE", "ZORA_TIMED"]}) {
        ...SaleStrategy
      }
    }
}`;

const FRAGMENTS = `
${NFT_SALE_STRATEGY_FRAGMENT}
${TOKEN_FRAGMENT}
`;

export function buildNftTokenSalesQuery({
  tokenId,
  tokenAddress,
}: {
  tokenId?: GenericTokenIdTypes;
  tokenAddress: Address;
}): ISubgraphQuery<TokenQueryResult> {
  return {
    query: `
${FRAGMENTS}
query ($id: ID!) {
  zoraCreateToken(id: $id) {
    ...Token 
  }
}
`,
    variables: {
      id:
        tokenId !== undefined
          ? // Generic Token ID types all stringify down to the base numeric equivalent.
            `${tokenAddress.toLowerCase()}-${tokenId}`
          : `${tokenAddress.toLowerCase()}-0`,
    },
    parseResponseData: (responseData: any | undefined) =>
      responseData?.zoraCreateToken,
  };
}

export function buildContractTokensQuery({
  tokenAddress,
}: {
  tokenAddress: Address;
}): ISubgraphQuery<TokenQueryResult[]> {
  return {
    query: `
${FRAGMENTS}
query ($contract: Bytes!) {
  zoraCreateTokens(
     where: {address: $contract}
  ) {
     ...Token
  }
}
`,
    variables: {
      contract: tokenAddress.toLowerCase(),
    },
    parseResponseData: (responseData: any | undefined) =>
      responseData?.zoraCreateTokens,
  };
}
export function buildPremintsOfContractQuery({
  tokenAddress,
}: {
  tokenAddress: Address;
}): ISubgraphQuery<{ uid: string; tokenId: string }[]> {
  return {
    query: `
      query ($contractAddress: Bytes!) {
        premints(where:{contractAddress:$contractAddress}) {
          uid
          tokenId
        }
      }
    `,
    variables: {
      contractAddress: tokenAddress.toLowerCase(),
    },
    parseResponseData: (responseData: any | undefined) =>
      responseData?.premints,
  };
}
