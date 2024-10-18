import { Address } from "viem";
import { ISubgraphQuerier } from "../apis/subgraph-querier";
import { NetworkConfig, networkConfigByChain } from "src/apis/chain-constants";
import { GenericTokenIdTypes } from "src/types";
import {
  IOnchainMintGetter,
  SaleType,
  OnchainMintable,
  OnchainSalesStrategies,
  GetMintableReturn,
} from "./types";
import {
  buildContractTokensQuery,
  buildNftTokenSalesQuery,
  buildPremintsOfContractQuery,
  ERC20SaleStrategyResult,
  FixedPriceSaleStrategyResult,
  PresaleSalesStrategyResult,
  SalesStrategyResult,
  TokenQueryResult,
  ZoraTimedMinterSaleStrategyResult,
} from "./subgraph-queries";
import { SubgraphGetter } from "src/apis/subgraph-getter";

export const getApiNetworkConfigForChain = (chainId: number): NetworkConfig => {
  if (!networkConfigByChain[chainId]) {
    throw new Error(`chain id ${chainId} network not configured `);
  }
  return networkConfigByChain[chainId]!;
};
type ParsedSalesConfig = {
  salesStrategy: OnchainSalesStrategies;
  saleActive: boolean;
  saleEnd: bigint | undefined;
  secondaryMarketActive?: boolean;
};

function parseFixedPriceSalesConfig(
  fixedPrice: FixedPriceSaleStrategyResult["fixedPrice"],
  contractMintFee: bigint,
  blockTime: bigint,
): ParsedSalesConfig {
  const saleEnd = BigInt(fixedPrice.saleEnd);
  return {
    salesStrategy: {
      saleType: "fixedPrice",
      ...fixedPrice,
      maxTokensPerAddress: BigInt(fixedPrice.maxTokensPerAddress),
      pricePerToken: BigInt(fixedPrice.pricePerToken),
      mintFeePerQuantity: contractMintFee,
    },
    saleEnd,
    saleActive:
      BigInt(fixedPrice.saleStart) <= blockTime && BigInt(saleEnd) > blockTime,
  };
}

function parseERC20SalesConfig(
  erc20Minter: ERC20SaleStrategyResult["erc20Minter"],
  blockTime: bigint,
): ParsedSalesConfig {
  const saleEnd = BigInt(erc20Minter.saleEnd);
  return {
    salesStrategy: {
      saleType: "erc20",
      ...erc20Minter,
      maxTokensPerAddress: BigInt(erc20Minter.maxTokensPerAddress),
      pricePerToken: BigInt(erc20Minter.pricePerToken),
      mintFeePerQuantity: 0n,
    },
    saleEnd,
    saleActive:
      BigInt(erc20Minter.saleStart) <= blockTime && saleEnd > blockTime,
  };
}

function parsePresaleSalesConfig(
  presale: PresaleSalesStrategyResult["presale"],
  contractMintFee: bigint,
  blockTime: bigint,
): ParsedSalesConfig {
  const saleEnd = BigInt(presale.presaleEnd);
  return {
    salesStrategy: {
      saleType: "allowlist",
      address: presale.address,
      merkleRoot: presale.merkleRoot,
      saleStart: presale.presaleStart,
      saleEnd: presale.presaleEnd,
      mintFeePerQuantity: contractMintFee,
    },
    saleEnd,
    saleActive:
      BigInt(presale.presaleStart) <= blockTime && saleEnd > blockTime,
  };
}

function parseZoraTimedSalesConfig(
  zoraTimedMinter: ZoraTimedMinterSaleStrategyResult["zoraTimedMinter"],
  blockTime: bigint,
): ParsedSalesConfig {
  const saleEnd = BigInt(zoraTimedMinter.saleEnd);
  const hasSaleEnd = saleEnd > 0n;
  return {
    salesStrategy: {
      saleType: "timed",
      address: zoraTimedMinter.address,
      mintFee: BigInt(zoraTimedMinter.mintFee),
      saleStart: zoraTimedMinter.saleStart,
      saleEnd: zoraTimedMinter.saleEnd,
      erc20Z: zoraTimedMinter.erc20Z.id,
      pool: zoraTimedMinter.erc20Z.pool,
      secondaryActivated: zoraTimedMinter.secondaryActivated,
      mintFeePerQuantity: BigInt(zoraTimedMinter.mintFee),
      marketCountdown: zoraTimedMinter.marketCountdown
        ? BigInt(zoraTimedMinter.marketCountdown)
        : undefined,
      minimumMarketEth: zoraTimedMinter.minimumMarketEth
        ? BigInt(zoraTimedMinter.minimumMarketEth)
        : undefined,
    },
    saleEnd: hasSaleEnd ? saleEnd : undefined,
    secondaryMarketActive: zoraTimedMinter.secondaryActivated,
    saleActive:
      BigInt(zoraTimedMinter.saleStart) <= blockTime &&
      (hasSaleEnd ? saleEnd > blockTime : true),
  };
}

function parseSalesConfig(
  targetStrategy: SalesStrategyResult,
  contractMintFee: bigint,
  blockTime: bigint,
): ParsedSalesConfig {
  switch (targetStrategy.type) {
    case "FIXED_PRICE":
      return parseFixedPriceSalesConfig(
        targetStrategy.fixedPrice,
        contractMintFee,
        blockTime,
      );
    case "ERC_20_MINTER":
      return parseERC20SalesConfig(targetStrategy.erc20Minter, blockTime);
    case "PRESALE":
      return parsePresaleSalesConfig(
        targetStrategy.presale,
        contractMintFee,
        blockTime,
      );
    case "ZORA_TIMED":
      return parseZoraTimedSalesConfig(
        targetStrategy.zoraTimedMinter,
        blockTime,
      );
    default:
      throw new Error("Unknown saleType");
  }
}

function getTargetStrategy({
  tokenId,
  preferredSaleType,
  token,
  blockTime,
  contractMintFee,
}: {
  tokenId?: GenericTokenIdTypes;
  preferredSaleType?: SaleType;
  token: TokenQueryResult;
  blockTime: bigint;
  contractMintFee: bigint;
}): ParsedSalesConfig | undefined {
  const allStrategies =
    (typeof tokenId !== "undefined"
      ? token.salesStrategies
      : token.contract.salesStrategies) || [];

  const parsedStrategies = allStrategies.map((strategy) =>
    parseSalesConfig(strategy, contractMintFee, blockTime),
  );

  const stillValidSalesStrategies = parsedStrategies.filter(
    (strategy) => strategy.saleActive || strategy.secondaryMarketActive,
  );

  const saleStrategies = stillValidSalesStrategies.sort((a, b) =>
    (a.saleEnd ?? 0n) > (b.saleEnd ?? 0n) ? 1 : -1,
  );

  let targetStrategy: ParsedSalesConfig | undefined;

  if (!preferredSaleType) {
    return saleStrategies[0];
  } else {
    targetStrategy = saleStrategies.find(
      ({ salesStrategy }) => salesStrategy.saleType === preferredSaleType,
    );
    if (!targetStrategy) {
      const targetStrategy = saleStrategies.find(
        ({ salesStrategy }) =>
          salesStrategy.saleType === "timed" ||
          salesStrategy.saleType === "fixedPrice" ||
          salesStrategy.saleType === "erc20",
      );
      if (!targetStrategy) throw new Error("Cannot find valid sale strategy");
      return targetStrategy;
    }
  }

  return targetStrategy;
}

export class SubgraphMintGetter
  extends SubgraphGetter
  implements IOnchainMintGetter
{
  constructor(chainId: number, subgraphQuerier?: ISubgraphQuerier) {
    super(chainId, subgraphQuerier);
  }

  async getContractMintFee(contract: TokenQueryResult["contract"]) {
    return BigInt(contract.mintFeePerQuantity);
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

function getTargetStrategyAndMintFeeAndSaleActive({
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
    contractMintFee: defaultMintFee,
  });

  return targetStrategy;
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
}): GetMintableReturn {
  const salesStrategyAndMintInfo = getTargetStrategyAndMintFeeAndSaleActive({
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
    salesConfigAndTokenInfo: {
      ...tokenInfo,
      salesConfig: salesStrategyAndMintInfo?.salesStrategy,
    },
    primaryMintActive: salesStrategyAndMintInfo?.saleActive ?? false,
    primaryMintEnd: salesStrategyAndMintInfo?.saleEnd,
    secondaryMarketActive:
      salesStrategyAndMintInfo?.secondaryMarketActive ?? false,
  };
}

function parseTokenInfo({
  token,
}: {
  token: TokenQueryResult;
}): Omit<OnchainMintable, "primaryMintActive" | "primaryMintEnd"> {
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
