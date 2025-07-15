import {
  Account,
  Address,
  PublicClient,
  SimulateContractParameters,
  Transport,
  Chain,
} from "viem";

export type GenericTokenIdTypes = number | bigint | string;

export type IPublicClient = Pick<
  PublicClient<Transport, Chain>,
  "readContract" | "getBlock" | "simulateContract" | "getBalance" | "chain"
>;

export type WithPublicClient<T> = T & {
  /** Public client used to read data from the blockchain.  Chain id will determine which chain is used. */
  publicClient: IPublicClient;
};

export type SimulateContractParametersWithAccount = SimulateContractParameters<
  any,
  any,
  any,
  any,
  any,
  Account | Address
>;
