import { IHttpClient } from "./http-api-base";

export interface ISubgraphQuerier {
  query: (params: {
    subgraphUrl: string;
    query: string;
    variables?: Record<string, any>;
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
