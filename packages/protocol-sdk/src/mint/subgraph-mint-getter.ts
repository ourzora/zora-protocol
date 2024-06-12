import { Address } from "viem";
import {
  httpClient as defaultHttpClient,
  IHttpClient,
} from "../apis/http-api-base";
import { NetworkConfig, networkConfigByChain } from "src/apis/chain-constants";
import { GenericTokenIdTypes } from "src/types";
import { IMintGetter, SalesConfigAndTokenInfo, SaleType } from "./types";
import { NFT_SALE_QUERY } from "src/constants";

type FixedPriceSaleStrategyResult = {
  address: Address;
  pricePerToken: string;
  saleEnd: string;
  saleStart: string;
  maxTokensPerAddress: string;
};

type ERC20SaleStrategyResult = FixedPriceSaleStrategyResult & {
  currency: Address;
};

type SalesStrategyResult =
  | {
      type: "FIXED_PRICE";
      fixedPrice: FixedPriceSaleStrategyResult;
    }
  | {
      type: "ERC_20_MINTER";
      erc20Minter: ERC20SaleStrategyResult;
    };

type TokenQueryResult = {
  tokenId?: string;
  salesStrategies?: SalesStrategyResult[];
  contract: {
    mintFeePerQuantity: "string";
    salesStrategies: SalesStrategyResult[];
  };
};

export const getApiNetworkConfigForChain = (chainId: number): NetworkConfig => {
  if (!networkConfigByChain[chainId]) {
    throw new Error(`chain id ${chainId} network not configured `);
  }
  return networkConfigByChain[chainId]!;
};

export class SubgraphMintGetter implements IMintGetter {
  httpClient: IHttpClient;
  networkConfig: NetworkConfig;

  constructor(chainId: number, httpClient?: IHttpClient) {
    this.httpClient = httpClient || defaultHttpClient;
    this.networkConfig = getApiNetworkConfigForChain(chainId);
  }

  async getSalesConfigAndTokenInfo({
    tokenAddress,
    tokenId,
    saleType,
  }: {
    tokenAddress: Address;
    tokenId?: GenericTokenIdTypes;
    saleType?: SaleType;
  }): Promise<SalesConfigAndTokenInfo> {
    const { retries, post } = this.httpClient;
    return retries(async () => {
      const response = await post<any>(this.networkConfig.subgraphUrl, {
        query: NFT_SALE_QUERY,
        variables: {
          id:
            tokenId !== undefined
              ? // Generic Token ID types all stringify down to the base numeric equivalent.
                `${tokenAddress.toLowerCase()}-${tokenId}`
              : `${tokenAddress.toLowerCase()}-0`,
        },
      });

      const token = response.data?.zoraCreateToken as TokenQueryResult;

      if (!token) {
        throw new Error("Cannot find a token to mint");
      }

      const allStrategies =
        (typeof tokenId !== "undefined"
          ? token.salesStrategies
          : token.contract.salesStrategies) || [];

      const saleStrategies = allStrategies.sort((a, b) =>
        BigInt(
          a.type === "ERC_20_MINTER"
            ? a.erc20Minter.saleEnd
            : a.fixedPrice.saleEnd,
        ) >
        BigInt(
          b.type === "FIXED_PRICE"
            ? b.fixedPrice.saleEnd
            : b.erc20Minter.saleEnd,
        )
          ? 1
          : -1,
      );

      let targetStrategy: SalesStrategyResult | undefined;

      if (!saleType) {
        targetStrategy = saleStrategies[0];
        if (!targetStrategy) {
          throw new Error("Cannot find sale strategy");
        }
      } else {
        const mappedSaleType =
          saleType === "erc20" ? "ERC_20_MINTER" : "FIXED_PRICE";
        targetStrategy = saleStrategies.find(
          (strategy: SalesStrategyResult) => strategy.type === mappedSaleType,
        );
        if (!targetStrategy) {
          throw new Error(`Cannot find sale strategy for ${mappedSaleType}`);
        }
      }

      if (targetStrategy.type === "FIXED_PRICE") {
        return {
          salesConfig: {
            saleType: "fixedPrice",
            ...targetStrategy.fixedPrice,
            maxTokensPerAddress: BigInt(
              targetStrategy.fixedPrice.maxTokensPerAddress,
            ),
            pricePerToken: BigInt(targetStrategy.fixedPrice.pricePerToken),
          },
          mintFeePerQuantity: BigInt(token.contract.mintFeePerQuantity),
        };
      }
      if (targetStrategy.type === "ERC_20_MINTER") {
        return {
          salesConfig: {
            saleType: "erc20",
            ...targetStrategy.erc20Minter,
            maxTokensPerAddress: BigInt(
              targetStrategy.erc20Minter.maxTokensPerAddress,
            ),
            pricePerToken: BigInt(targetStrategy.erc20Minter.pricePerToken),
          },
          mintFeePerQuantity: BigInt(token.contract.mintFeePerQuantity),
        };
      }

      throw new Error("Invalid saleType");
    });
  }
}
