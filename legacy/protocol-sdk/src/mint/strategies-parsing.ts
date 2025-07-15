import { GenericTokenIdTypes } from "src/types";
import {
  SaleType,
  OnchainMintable,
  OnchainSalesStrategies,
  GetMintableReturn,
  ZoraTimedSaleStrategy,
} from "./types";
import {
  ERC20SaleStrategyResult,
  FixedPriceSaleStrategyResult,
  PresaleSalesStrategyResult,
  SalesStrategyResult,
  TokenQueryResult,
  ZoraTimedMinterSaleStrategyResult,
} from "./subgraph-queries";

type ParsedSalesConfig = {
  salesStrategy: OnchainSalesStrategies;
  // saleActive: boolean;
  saleEnd: bigint | undefined;
  saleStart: bigint;
};

function parseFixedPriceSalesConfig(
  fixedPrice: FixedPriceSaleStrategyResult["fixedPrice"],
  contractMintFee: bigint,
  // blockTime: bigint,
): ParsedSalesConfig {
  // const saleEnd = BigInt(fixedPrice.saleEnd);
  return {
    salesStrategy: {
      saleType: "fixedPrice",
      ...fixedPrice,
      maxTokensPerAddress: BigInt(fixedPrice.maxTokensPerAddress),
      pricePerToken: BigInt(fixedPrice.pricePerToken),
      mintFeePerQuantity: contractMintFee,
    },
    saleEnd: BigInt(fixedPrice.saleEnd),
    saleStart: BigInt(fixedPrice.saleStart),
    // saleActive:
    //   BigInt(fixedPrice.saleStart) <= blockTime && BigInt(saleEnd) > blockTime,
  };
}

function parseERC20SalesConfig(
  erc20Minter: ERC20SaleStrategyResult["erc20Minter"],
  // blockTime: bigint,
): ParsedSalesConfig {
  // const saleEnd = BigInt(erc20Minter.saleEnd);
  return {
    salesStrategy: {
      saleType: "erc20",
      ...erc20Minter,
      maxTokensPerAddress: BigInt(erc20Minter.maxTokensPerAddress),
      pricePerToken: BigInt(erc20Minter.pricePerToken),
      mintFeePerQuantity: 0n,
    },
    saleEnd: BigInt(erc20Minter.saleEnd),
    saleStart: BigInt(erc20Minter.saleStart),
    // saleActive:
    //   BigInt(erc20Minter.saleStart) <= blockTime && saleEnd > blockTime,
  };
}

function parsePresaleSalesConfig(
  presale: PresaleSalesStrategyResult["presale"],
  contractMintFee: bigint,
  // blockTime: bigint,
): ParsedSalesConfig {
  // const saleEnd = BigInt(presale.presaleEnd);
  return {
    salesStrategy: {
      saleType: "allowlist",
      address: presale.address,
      merkleRoot: presale.merkleRoot,
      saleStart: presale.presaleStart,
      saleEnd: presale.presaleEnd,
      mintFeePerQuantity: contractMintFee,
    },
    saleEnd: BigInt(presale.presaleEnd),
    saleStart: BigInt(presale.presaleStart),
    // saleActive:
    // BigInt(presale.presaleStart) <= blockTime && saleEnd > blockTime,
  };
}

function parseZoraTimedSalesConfig(
  zoraTimedMinter: ZoraTimedMinterSaleStrategyResult["zoraTimedMinter"],
  // blockTime: bigint,
): ParsedSalesConfig {
  const saleEnd = BigInt(zoraTimedMinter.saleEnd);
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
    saleEnd: saleEnd > 0n ? saleEnd : undefined,
    saleStart: BigInt(zoraTimedMinter.saleStart),
    // saleActive:
    //   BigInt(zoraTimedMinter.saleStart) <= blockTime &&
    // (hasSaleEnd ? saleEnd > blockTime : true),
  };
}

function parseSalesConfig(
  targetStrategy: SalesStrategyResult,
  contractMintFee: bigint,
): ParsedSalesConfig {
  switch (targetStrategy.type) {
    case "FIXED_PRICE":
      return parseFixedPriceSalesConfig(
        targetStrategy.fixedPrice,
        contractMintFee,
        // blockTime,
      );
    case "ERC_20_MINTER":
      return parseERC20SalesConfig(targetStrategy.erc20Minter);
    case "PRESALE":
      return parsePresaleSalesConfig(
        targetStrategy.presale,
        contractMintFee,
        // blockTime,
      );
    case "ZORA_TIMED":
      return parseZoraTimedSalesConfig(
        targetStrategy.zoraTimedMinter,
        // blockTime,
      );
    default:
      throw new Error("Unknown saleType");
  }
}

function isPrimaryMintActive(sale: ParsedSalesConfig, blockTime: bigint) {
  if (sale.saleStart > blockTime) return false;
  if (!sale.saleEnd) return true;

  return sale.saleEnd > blockTime;
}

function isSecondaryMinter(
  result: OnchainSalesStrategies,
): result is ZoraTimedSaleStrategy {
  return result.saleType === "timed";
}

function isSecondaryMarketActive(sale: ParsedSalesConfig) {
  const salesStrategy = sale.salesStrategy;
  if (isSecondaryMinter(salesStrategy)) {
    return salesStrategy.secondaryActivated;
  }
  return false;
}

type WithPrimaryAndSecondaryMintActive = {
  strategy: ParsedSalesConfig;
  primaryMintActive: boolean;
  secondaryMarketActive: boolean;
};

function getTargetStrategy({
  preferredSaleType,
  blockTime,
  parsedStrategies,
}: {
  preferredSaleType?: SaleType;
  blockTime: bigint;
  parsedStrategies: ParsedSalesConfig[];
}): WithPrimaryAndSecondaryMintActive | undefined {
  const withPrimaryAndSecondaryMintActive = parsedStrategies.map(
    (strategy) => ({
      strategy,
      primaryMintActive: isPrimaryMintActive(strategy, blockTime),
      secondaryMarketActive: isSecondaryMarketActive(strategy),
    }),
  );
  const stillValidSalesStrategies = withPrimaryAndSecondaryMintActive.filter(
    ({ primaryMintActive, secondaryMarketActive }) =>
      primaryMintActive || secondaryMarketActive,
  );

  const saleStrategies = stillValidSalesStrategies.sort((a, b) =>
    (a.strategy.saleEnd ?? 0n) > (b.strategy.saleEnd ?? 0n) ? 1 : -1,
  );

  let targetStrategy: WithPrimaryAndSecondaryMintActive | undefined;

  if (!preferredSaleType) {
    return saleStrategies[0];
  } else {
    targetStrategy = saleStrategies.find(
      ({ strategy: { salesStrategy } }) =>
        salesStrategy.saleType === preferredSaleType,
    );
    if (!targetStrategy) {
      targetStrategy = saleStrategies.find(
        ({ strategy: { salesStrategy } }) =>
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

export function findTargetStrategyWithPrimaryOrSecondarySaleActive({
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
  const allStrategies =
    (typeof tokenId !== "undefined"
      ? token.salesStrategies
      : token.contract.salesStrategies) || [];

  const parsedStrategies = allStrategies.map((strategy) =>
    parseSalesConfig(strategy, defaultMintFee),
  );

  const targetStrategy = getTargetStrategy({
    preferredSaleType: preferredSaleType,
    blockTime,
    parsedStrategies,
  });

  return targetStrategy;
}

export function parseAndFilterTokenQueryResult({
  token,
  tokenId,
  preferredSaleType,
  blockTime,
}: {
  token: TokenQueryResult;
  tokenId?: GenericTokenIdTypes;
  preferredSaleType?: SaleType;
  blockTime: bigint;
}): GetMintableReturn {
  const defaultMintFee = BigInt(token.contract.mintFeePerQuantity);
  const salesStrategyAndMintInfo =
    findTargetStrategyWithPrimaryOrSecondarySaleActive({
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
      salesConfig: salesStrategyAndMintInfo?.strategy.salesStrategy,
    },
    primaryMintActive: salesStrategyAndMintInfo?.primaryMintActive ?? false,
    primaryMintEnd: salesStrategyAndMintInfo?.strategy.saleEnd,
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
