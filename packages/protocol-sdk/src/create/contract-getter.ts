import { NetworkConfig } from "src/apis/chain-constants";
import {
  ISubgraphQuerier,
  ISubgraphQuery,
  SubgraphQuerier,
} from "src/apis/subgraph-querier";
import { httpClient as defaultHttpClient } from "../apis/http-api-base";
import { Address } from "viem";
import { getApiNetworkConfigForChain } from "src/mint/subgraph-mint-getter";
import { buildContractInfoQuery } from "./subgraph-queries";
import { retriesGeneric } from "src/retries";

export interface IContractGetter {
  getContractInfo: (params: {
    contractAddress: Address;
    retries?: number;
  }) => Promise<{
    name: string;
    contractVersion: string;
    nextTokenId: bigint;
    mintFee: bigint;
  }>;
}

export class SubgraphContractGetter implements IContractGetter {
  public readonly subgraphQuerier: ISubgraphQuerier;
  networkConfig: NetworkConfig;

  constructor(chainId: number, subgraphQuerier?: ISubgraphQuerier) {
    this.subgraphQuerier =
      subgraphQuerier || new SubgraphQuerier(defaultHttpClient);
    this.networkConfig = getApiNetworkConfigForChain(chainId);
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

  async getContractInfo({
    contractAddress,
    retries = 1,
  }: {
    contractAddress: Address;
    retries?: number;
  }): Promise<{
    name: string;
    contractVersion: string;
    nextTokenId: bigint;
    mintFee: bigint;
  }> {
    const tryFn = async () => {
      const responseData = await this.querySubgraphWithRetries(
        buildContractInfoQuery({ contractAddress }),
      );
      if (!responseData) {
        console.log("could not find contract");
        throw new Error("Cannot find contract");
      }
      return responseData;
    };

    const responseData = await retriesGeneric({
      tryFn,
      maxTries: retries,
      linearBackoffMS: 1000,
    });

    const nextTokenId =
      responseData.tokens.length === 0
        ? 1n
        : BigInt(responseData.tokens[0]!.tokenId) + 1n;

    return {
      name: responseData.name,
      contractVersion: responseData.contractVersion,
      mintFee: BigInt(responseData.mintFeePerQuantity),
      nextTokenId,
    };
  }
}
