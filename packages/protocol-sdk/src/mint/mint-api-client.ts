import * as httpClientBase from "../apis/http-api-base";
import { paths } from "../apis/generated/discover-api-types";
import { ZORA_API_BASE } from "../constants";
import { NetworkConfig, networkConfigByChain } from "src/apis/chain-constants";
import { Address } from "viem";

export type MintableGetToken =
  paths["/mintables/{chain_name}/{collection_address}"];
type MintableGetTokenPathParameters =
  MintableGetToken["get"]["parameters"]["path"];
type MintableGetTokenGetQueryParameters =
  MintableGetToken["get"]["parameters"]["query"];
export type MintableGetTokenResponse =
  MintableGetToken["get"]["responses"][200]["content"]["application/json"];

function encodeQueryParameters(params: Record<string, string>) {
  return new URLSearchParams(params).toString();
}

export const getApiNetworkConfigForChain = (chainId: number): NetworkConfig => {
  if (!networkConfigByChain[chainId]) {
    throw new Error(`chain id ${chainId} network not configured `);
  }
  return networkConfigByChain[chainId]!;
};

export class MintAPIClient {
  httpClient: typeof httpClientBase;
  networkConfig: NetworkConfig;

  constructor(chainId: number, httpClient?: typeof httpClientBase) {
    this.httpClient = httpClient || httpClientBase;
    this.networkConfig = getApiNetworkConfigForChain(chainId);
  }

  async getMintable(
    path: MintableGetTokenPathParameters,
    query: MintableGetTokenGetQueryParameters,
  ): Promise<MintableGetTokenResponse> {
    const httpClient = this.httpClient;
    return httpClient.retries(() => {
      return httpClient.get<MintableGetTokenResponse>(
        `${ZORA_API_BASE}discover/mintables/${path.chain_name}/${
          path.collection_address
        }${query?.token_id ? `?${encodeQueryParameters(query)}` : ""}`,
      );
    });
  }

  async getSalesConfigFixedPrice({
    contractAddress,
    tokenId,
  }: {
    contractAddress: string;
    tokenId: bigint;
  }): Promise<undefined | string> {
    const { retries, post } = this.httpClient;
    return retries(async () => {
      const response = await post<any>(this.networkConfig.subgraphUrl, {
        query:
          "query($id: ID!) {\n  zoraCreateToken(id: $id) {\n    id\n    salesStrategies{\n      fixedPrice {\n        address\n      }\n    }\n  }\n}",
        variables: {
          id: `${contractAddress.toLowerCase()}-${tokenId.toString()}`,
        },
      });
      return response.zoraCreateToken?.salesStrategies?.find(() => true)
        ?.fixedPriceMinterAddress;
    });
  }

  async getMintableForToken({
    tokenContract,
    tokenId,
  }: {
    tokenContract: Address;
    tokenId?: bigint | number | string;
  }) {
    return await this.getMintable(
      {
        chain_name: this.networkConfig.zoraBackendChainName,
        collection_address: tokenContract,
      },
      { token_id: tokenId?.toString() },
    );
  }
}
