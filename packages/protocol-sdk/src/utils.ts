import {
  Abi,
  Account,
  Address,
  Chain,
  ContractFunctionArgs,
  ContractFunctionName,
  PublicClient as BasePublicClient,
  SimulateContractParameters,
  Transport,
  createPublicClient,
  http,
} from "viem";
import {
  IHttpClient,
  httpClient as defaultHttpClient,
} from "./apis/http-api-base";

export const makeSimulateContractParamaters = <
  const abi extends Abi | readonly unknown[],
  functionName extends ContractFunctionName<abi, "nonpayable" | "payable">,
  args extends ContractFunctionArgs<
    abi,
    "nonpayable" | "payable",
    functionName
  >,
  chainOverride extends Chain | undefined,
  accountOverride extends Account | Address | undefined = undefined,
>(
  args: SimulateContractParameters<
    abi,
    functionName,
    args,
    Chain,
    chainOverride,
    accountOverride
  >,
) => args;

export type PublicClient = BasePublicClient<Transport, Chain>;

export type ClientConfig = {
  chain: Chain;
  publicClient?: PublicClient;
  httpClient?: IHttpClient;
};

export function setupClient({ chain, httpClient, publicClient }: ClientConfig) {
  return {
    chain,
    httpClient: httpClient || defaultHttpClient,
    publicClient:
      publicClient || createPublicClient({ chain, transport: http() }),
  };
}
