import { Address } from "viem";
import {
  httpClient as defaultHttpClient,
  IHttpClient,
} from "../apis/http-api-base";
import { NetworkConfig, networkConfigByChain } from "src/apis/chain-constants";
import { GenericTokenIdTypes } from "src/types";
import {
  IOnchainMintGetter,
  SaleType,
  OnchainMintable,
  OnchainSalesConfigAndTokenInfo,
  OnchainSalesStrategies,
  isErc20SaleStrategy,
} from "./types";
import { querySubgraphWithRetries } from "src/utils";
import {
  buildContractTokensQuery,
  buildNftTokenSalesQuery,
  buildPremintsOfContractQuery,
  ISubgraphQuery,
  SalesStrategyResult,
  TokenQueryResult,
} from "./subgraph-queries";

export const getApiNetworkConfigForChain = (chainId: number): NetworkConfig => {
  if (!networkConfigByChain[chainId]) {
    throw new Error(`chain id ${chainId} network not configured `);
  }
  return networkConfigByChain[chainId]!;
};

function parseSalesConfig(
  targetStrategy: SalesStrategyResult,
): OnchainSalesStrategies {
  if (targetStrategy.type === "FIXED_PRICE")
    return {
      saleType: "fixedPrice",
      ...targetStrategy.fixedPrice,
      maxTokensPerAddress: BigInt(
        targetStrategy.fixedPrice.maxTokensPerAddress,
      ),
      pricePerToken: BigInt(targetStrategy.fixedPrice.pricePerToken),
    };

  if (targetStrategy.type === "ERC_20_MINTER") {
    return {
      saleType: "erc20",
      ...targetStrategy.erc20Minter,
      maxTokensPerAddress: BigInt(
        targetStrategy.erc20Minter.maxTokensPerAddress,
      ),
      pricePerToken: BigInt(targetStrategy.erc20Minter.pricePerToken),
    };
  }

  throw new Error("Unknown saleType");
}

function getSaleEnd(a: SalesStrategyResult) {
  return BigInt(
    a.type === "ERC_20_MINTER" ? a.erc20Minter.saleEnd : a.fixedPrice.saleEnd,
  );
}

function getTargetStrategy({
  tokenId,
  preferredSaleType,
  token,
}: {
  tokenId?: GenericTokenIdTypes;
  preferredSaleType?: SaleType;
  token: TokenQueryResult;
}) {
  const allStrategies =
    (typeof tokenId !== "undefined"
      ? token.salesStrategies
      : token.contract.salesStrategies) || [];

  const saleStrategies = allStrategies.sort((a, b) =>
    getSaleEnd(a) > getSaleEnd(b) ? 1 : -1,
  );

  let targetStrategy: SalesStrategyResult | undefined;

  if (!preferredSaleType) {
    targetStrategy = saleStrategies[0];
    if (!targetStrategy) {
      throw new Error("Cannot find sale strategy");
    }
  } else {
    const mappedSaleType =
      preferredSaleType === "erc20" ? "ERC_20_MINTER" : "FIXED_PRICE";
    targetStrategy = saleStrategies.find(
      (strategy: SalesStrategyResult) => strategy.type === mappedSaleType,
    );
    if (!targetStrategy) {
      const targetStrategy = saleStrategies.find(
        (strategy: SalesStrategyResult) =>
          strategy.type === "FIXED_PRICE" || strategy.type === "ERC_20_MINTER",
      );
      if (!targetStrategy) throw new Error("Cannot find valid sale strategy");
      return targetStrategy;
    }
  }

  return targetStrategy;
}
export class SubgraphMintGetter implements IOnchainMintGetter {
  httpClient: IHttpClient;
  networkConfig: NetworkConfig;

  constructor(chainId: number, httpClient?: IHttpClient) {
    this.httpClient = httpClient || defaultHttpClient;
    this.networkConfig = getApiNetworkConfigForChain(chainId);
  }

  async querySubgraphWithRetries<T>({
    query,
    variables,
    parseResponseData,
  }: ISubgraphQuery<T>) {
    const responseData = await querySubgraphWithRetries({
      httpClient: this.httpClient,
      subgraphUrl: this.networkConfig.subgraphUrl,
      query,
      variables,
    });

    return parseResponseData(responseData);
  }

  getMintable: IOnchainMintGetter["getMintable"] = async ({
    tokenAddress,
    tokenId,
    preferredSaleType: saleType,
  }) => {
    const token = await this.querySubgraphWithRetries(
      buildNftTokenSalesQuery({
        tokenId,
        tokenAddress,
      }),
    );

    if (!token) {
      throw new Error("Cannot find token");
    }

    return parseTokenQueryResult({
      token,
      tokenId,
      preferredSaleType: saleType,
    });
  };

  async getContractMintable({
    tokenAddress,
    preferredSaleType,
  }: {
    tokenAddress: Address;
    preferredSaleType?: SaleType;
  }) {
    const tokens = await this.querySubgraphWithRetries(
      buildContractTokensQuery({
        tokenAddress,
      }),
    );

    if (!tokens) return [];

    return tokens
      .filter((x) => x.tokenId !== "0")
      .map((token) =>
        parseTokenQueryResult({
          token,
          tokenId: token.tokenId,
          preferredSaleType,
        }),
      );
  }

  async getContractPremintTokenIds({
    tokenAddress,
  }: {
    tokenAddress: Address;
  }) {
    const premints = await this.querySubgraphWithRetries(
      buildPremintsOfContractQuery({
        tokenAddress,
      }),
    );

    return (
      premints?.map((premint) => ({
        tokenId: BigInt(premint.tokenId),
        uid: +premint.uid,
      })) || []
    );
  }
}

function parseTokenQueryResult({
  token,
  tokenId,
  preferredSaleType,
}: {
  token: TokenQueryResult;
  tokenId?: GenericTokenIdTypes;
  preferredSaleType?: SaleType;
}): OnchainSalesConfigAndTokenInfo {
  const targetStrategy = getTargetStrategy({
    tokenId,
    preferredSaleType: preferredSaleType,
    token,
  });

  const tokenInfo = parseTokenInfo(token);

  const salesConfig = parseSalesConfig(targetStrategy);

  if (isErc20SaleStrategy(salesConfig)) {
    tokenInfo.mintFeePerQuantity = 0n;
  }

  return {
    ...tokenInfo,
    salesConfig,
  };
}

function parseTokenInfo(token: TokenQueryResult): OnchainMintable {
  return {
    contract: {
      address: token.contract.address,
      name: token.contract.name,
      URI: token.contract.contractURI,
    },
    tokenURI: token.uri,
    tokenId: token.tokenId ? BigInt(token.tokenId) : undefined,
    mintType: token.tokenStandard === "ERC721" ? "721" : "1155",
    creator: token.creator,
    totalMinted: BigInt(token.totalMinted),
    maxSupply: BigInt(token.maxSupply),
    mintFeePerQuantity: BigInt(token.contract.mintFeePerQuantity),
    contractVersion: token.contract.contractVersion,
  };
}
