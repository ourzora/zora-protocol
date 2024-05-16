import {
  httpClient as defaultHttpClient,
  IHttpClient,
} from "../apis/http-api-base";
import { NetworkConfig, networkConfigByChain } from "src/apis/chain-constants";
import { GenericTokenIdTypes } from "src/types";
import { Address } from "viem";

type FixedPriceSaleStrategyResult = {
  address: Address;
  pricePerToken: string;
  saleEnd: string;
  saleStart: string;
  maxTokensPerAddress: string;
};

type SaleStrategyResult = {
  fixedPrice: FixedPriceSaleStrategyResult;
};

export type SalesConfigAndTokenInfo = {
  fixedPrice: FixedPriceSaleStrategyResult;
  mintFeePerQuantity: bigint;
};

export const getApiNetworkConfigForChain = (chainId: number): NetworkConfig => {
  if (!networkConfigByChain[chainId]) {
    throw new Error(`chain id ${chainId} network not configured `);
  }
  return networkConfigByChain[chainId]!;
};

export class MintAPIClient {
  httpClient: IHttpClient;
  networkConfig: NetworkConfig;

  constructor(chainId: number, httpClient?: IHttpClient) {
    this.httpClient = httpClient || defaultHttpClient;
    this.networkConfig = getApiNetworkConfigForChain(chainId);
  }

  async getSalesConfigAndTokenInfo({
    tokenAddress,
    tokenId,
  }: {
    tokenAddress: Address;
    tokenId?: GenericTokenIdTypes;
  }): Promise<SalesConfigAndTokenInfo> {
    const { retries, post } = this.httpClient;
    return retries(async () => {
      const response = await post<any>(this.networkConfig.subgraphUrl, {
        query: `
          fragment SaleStrategy on SalesStrategyConfig {
            type
            fixedPrice {
              address
              pricePerToken
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
                salesStrategies(where: { type: "FIXED_PRICE" }) {
                  ...SaleStrategy
                }
              }
              salesStrategies(where: { type: "FIXED_PRICE" }) {
                ...SaleStrategy
              }
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
      });

      const token = response.data?.zoraCreateToken;

      if (!token) {
        throw new Error("Cannot find a token to mint");
      }

      const saleStrategies: SaleStrategyResult[] =
        tokenId !== undefined
          ? token.salesStrategies
          : token.contract.salesStrategies;

      const fixedPrice = saleStrategies
        ?.sort((a: SaleStrategyResult, b: SaleStrategyResult) =>
          BigInt(a.fixedPrice.saleEnd) > BigInt(b.fixedPrice.saleEnd) ? 1 : -1,
        )
        ?.find(() => true)?.fixedPrice;

      if (!fixedPrice) {
        throw new Error("Cannot find fixed price sale strategy");
      }

      return {
        fixedPrice,
        mintFeePerQuantity: BigInt(token.contract.mintFeePerQuantity),
      };
    });
  }
}
