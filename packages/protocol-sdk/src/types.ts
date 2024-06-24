import {
  Account,
  Address,
  PublicClient,
  SimulateContractParameters,
} from "viem";

export type GenericTokenIdTypes = number | bigint | string;

export type IPublicClient = Pick<PublicClient, "readContract">;

export type SimulateContractParametersWithAccount = SimulateContractParameters<
  any,
  any,
  any,
  any,
  any,
  Account | Address
>;
