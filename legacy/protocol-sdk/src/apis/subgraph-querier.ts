import { IHttpClient } from "./http-api-base";

export type ISubgraphQuery<T> = {
  query: string;
  variables: Record<string, any>;
  parseResponseData: (data: any | undefined) => T | undefined;
};

export interface ISubgraphQuerier {
  query: (params: {
    subgraphUrl: string;
    query: string;
    variables?: Record<string, any>;
    maxRetries?: number;
  }) => Promise<object | undefined>;
}

export class SubgraphQuerier implements ISubgraphQuerier {
  httpClient: IHttpClient;

  constructor(httpClient: IHttpClient) {
    this.httpClient = httpClient;
  }

  async query({
    subgraphUrl,
    query,
    variables,
  }: {
    subgraphUrl: string;
    query: string;
    variables?: Record<string, any>;
  }) {
    const { retries, post } = this.httpClient;

    const result = await retries(async () => {
      return await post<any>(subgraphUrl, {
        query,
        variables,
      });
    });

    return result?.data;
  }
}
