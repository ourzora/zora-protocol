import { getApiNetworkConfigForChain } from "./network-config";
import { NetworkConfig } from "./chain-constants";
import {
  ISubgraphQuerier,
  ISubgraphQuery,
  SubgraphQuerier,
} from "./subgraph-querier";
import { httpClient as defaultHttpClient } from "../apis/http-api-base";

export class SubgraphGetter {
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
}
