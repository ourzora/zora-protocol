import { Account, Address, PublicClient as BasePublicClient } from "viem";
import { IHttpClient } from "./apis/http-api-base";
import { SimulateContractParametersWithAccount } from "./types";

export const makeContractParameters = (
  args: SimulateContractParametersWithAccount,
) => args;

export type PublicClient = Pick<BasePublicClient, "readContract">;

export type ClientConfig = {
  /** The chain that the client is to run on. */
  chainId: number;
  /** Optional public client for the chain.  If not provide, it is created. */
  publicClient: PublicClient;
};

export function setupClient({ chainId, publicClient }: ClientConfig) {
  return {
    chainId,
    publicClient,
  };
}

export function mintRecipientOrAccount({
  mintRecipient,
  minterAccount,
}: {
  mintRecipient?: Address;
  minterAccount: Address | Account;
}): Address {
  return (
    mintRecipient ||
    (typeof minterAccount === "string" ? minterAccount : minterAccount.address)
  );
}

export type Concrete<Type> = {
  [Property in keyof Type]-?: Type[Property];
};

export async function querySubgraphWithRetries({
  httpClient,
  subgraphUrl,
  query,
  variables,
}: {
  httpClient: IHttpClient;
  subgraphUrl: string;
  query: string;
  variables: any;
}) {
  const { retries, post } = httpClient;

  const result = await retries(async () => {
    return await post<any>(subgraphUrl, {
      query,
      variables,
    });
  });

  return result?.data;
}
