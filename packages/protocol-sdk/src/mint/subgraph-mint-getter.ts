import { Address } from "viem";
import { httpClient as defaultHttpClient } from "../apis/http-api-base";
import {
  ISubgraphQuerier,
  ISubgraphQuery,
  SubgraphQuerier,
} from "../apis/subgraph-querier";
import { NetworkConfig, networkConfigByChain } from "src/apis/chain-constants";
import { GenericTokenIdTypes } from "src/types";
import {
  IOnchainMintGetter,
  SaleType,
  OnchainMintable,
  OnchainSalesConfigAndTokenInfo,
  OnchainSalesStrategies,
} from "./types";
import {
  buildContractTokensQuery,
  buildNftTokenSalesQuery,
  buildPremintsOfContractQuery,
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
  contractMintFee: bigint,
): OnchainSalesStrategies {
  if (targetStrategy.type === "FIXED_PRICE")
    return {
      saleType: "fixedPrice",
      ...targetStrategy.fixedPrice,
      maxTokensPerAddress: BigInt(
        targetStrategy.fixedPrice.maxTokensPerAddress,
      ),
      pricePerToken: BigInt(targetStrategy.fixedPrice.pricePerToken),
      mintFeePerQuantity: contractMintFee,
    };

  if (targetStrategy.type === "ERC_20_MINTER") {
    return {
      saleType: "erc20",
      ...targetStrategy.erc20Minter,
      maxTokensPerAddress: BigInt(
        targetStrategy.erc20Minter.maxTokensPerAddress,
      ),
      pricePerToken: BigInt(targetStrategy.erc20Minter.pricePerToken),
      mintFeePerQuantity: 0n,
    };
  }
  if (targetStrategy.type === "PRESALE") {
    return {
      saleType: "allowlist",
      address: targetStrategy.presale.address,
      merkleRoot: targetStrategy.presale.merkleRoot,
      saleStart: targetStrategy.presale.presaleStart,
      saleEnd: targetStrategy.presale.presaleEnd,
      mintFeePerQuantity: contractMintFee,
    };
  }
  if (targetStrategy.type === "ZORA_TIMED") {
    return {
      saleType: "timed",
      address: targetStrategy.zoraTimedMinter.address,
      mintFee: BigInt(targetStrategy.zoraTimedMinter.mintFee),
      saleStart: targetStrategy.zoraTimedMinter.saleStart,
      saleEnd: targetStrategy.zoraTimedMinter.saleEnd,
      erc20Z: targetStrategy.zoraTimedMinter.erc20Z.id,
      pool: targetStrategy.zoraTimedMinter.erc20Z.pool,
      secondaryActivated: targetStrategy.zoraTimedMinter.secondaryActivated,
      mintFeePerQuantity: BigInt(targetStrategy.zoraTimedMinter.mintFee),
    };
  }

  throw new Error("Unknown saleType");
}

function getSaleEnd(a: SalesStrategyResult) {
  if (a.type === "FIXED_PRICE") return BigInt(a.fixedPrice.saleEnd);
  if (a.type === "ERC_20_MINTER") return BigInt(a.erc20Minter.saleEnd);
  if (a.type === "ZORA_TIMED") return BigInt(a.zoraTimedMinter.saleEnd);
  return BigInt(a.presale.presaleEnd);
}

function strategyIsStillValid(
  strategy: SalesStrategyResult,
  blockTime: bigint,
): boolean {
  if (strategy.type === "FIXED_PRICE") {
    return BigInt(strategy.fixedPrice.saleEnd) > blockTime;
  }
  if (strategy.type === "ERC_20_MINTER") {
    return BigInt(strategy.erc20Minter.saleEnd) > blockTime;
  }
  if (strategy.type === "ZORA_TIMED") {
    return BigInt(strategy.zoraTimedMinter.saleEnd) > blockTime;
  }
  return BigInt(strategy.presale.presaleEnd) > blockTime;
}

function getTargetStrategy({
  tokenId,
  preferredSaleType,
  token,
  blockTime,
}: {
  tokenId?: GenericTokenIdTypes;
  preferredSaleType?: SaleType;
  token: TokenQueryResult;
  blockTime: bigint;
}): SalesStrategyResult | undefined {
  const allStrategies =
    (typeof tokenId !== "undefined"
      ? token.salesStrategies
      : token.contract.salesStrategies) || [];

  const stillValidSalesStrategies = allStrategies.filter((strategy) =>
    strategyIsStillValid(strategy, blockTime),
  );

  const saleStrategies = stillValidSalesStrategies.sort((a, b) =>
    getSaleEnd(a) > getSaleEnd(b) ? 1 : -1,
  );

  let targetStrategy: SalesStrategyResult | undefined;

  if (!preferredSaleType) {
    return saleStrategies[0];
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
  public readonly subgraphQuerier: ISubgraphQuerier;
  networkConfig: NetworkConfig;

  constructor(chainId: number, subgraphQuerier?: ISubgraphQuerier) {
    this.subgraphQuerier =
      subgraphQuerier || new SubgraphQuerier(defaultHttpClient);
    this.networkConfig = getApiNetworkConfigForChain(chainId);
  }

  async getContractMintFee(contract: TokenQueryResult["contract"]) {
    return BigInt(contract.mintFeePerQuantity);
  }

  async querySubgraphWithRetries<T>({
    query,
    variables,
    parseResponseData,
  }: ISubgraphQuery<T>) {
    const responseData = await this.subgraphQuerier.query({
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
    blockTime,
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

    const defaultMintFee = await this.getContractMintFee(token.contract);

    return parseTokenQueryResult({
      token: token,
      defaultMintFee,
      tokenId,
      preferredSaleType: saleType,
      blockTime,
    });
  };

  async getContractMintable({
    tokenAddress,
    preferredSaleType,
    blockTime,
  }: {
    tokenAddress: Address;
    preferredSaleType?: SaleType;
    blockTime: bigint;
  }) {
    const tokens = await this.querySubgraphWithRetries(
      buildContractTokensQuery({
        tokenAddress,
      }),
    );

    if (!tokens || tokens.length === 0) return [];

    const defaultMintFee = await this.getContractMintFee(tokens[0]!.contract);

    return tokens
      .filter((x) => x.tokenId !== "0")
      .map((token) =>
        parseTokenQueryResult({
          token,
          tokenId: token.tokenId,
          preferredSaleType,
          defaultMintFee,
          blockTime,
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

function getTargetStrategyAndMintFee({
  token,
  tokenId,
  preferredSaleType,
  defaultMintFee,
  blockTime,
}: {
  token: TokenQueryResult;
  tokenId?: GenericTokenIdTypes;
  preferredSaleType?: SaleType;
  defaultMintFee: bigint;
  blockTime: bigint;
}) {
  const targetStrategy = getTargetStrategy({
    tokenId,
    preferredSaleType: preferredSaleType,
    token,
    blockTime,
  });

  if (!targetStrategy) return undefined;

  const salesConfig = parseSalesConfig(targetStrategy, defaultMintFee);

  return salesConfig;
}

function parseTokenQueryResult({
  token,
  tokenId,
  preferredSaleType,
  defaultMintFee,
  blockTime,
}: {
  token: TokenQueryResult;
  tokenId?: GenericTokenIdTypes;
  preferredSaleType?: SaleType;
  defaultMintFee: bigint;
  blockTime: bigint;
}): OnchainSalesConfigAndTokenInfo {
  const salesConfig = getTargetStrategyAndMintFee({
    token,
    tokenId,
    preferredSaleType,
    defaultMintFee,
    blockTime,
  });

  const tokenInfo = parseTokenInfo({
    token,
  });

  return {
    ...tokenInfo,
    salesConfig,
  };
}

function parseTokenInfo({
  token,
}: {
  token: TokenQueryResult;
}): OnchainMintable {
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
    contractVersion: token.contract.contractVersion,
  };
}
