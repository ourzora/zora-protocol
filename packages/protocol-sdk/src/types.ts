import { Account, Address, SimulateContractParameters } from "viem";
import { PublicClient } from "src/utils";

export type GenericTokenIdTypes = number | bigint | string;

export type IPublicClient = Pick<
  PublicClient,
  "readContract" | "getBlock" | "simulateContract" | "getBalance"
>;

export type SimulateContractParametersWithAccount = SimulateContractParameters<
  any,
  any,
  any,
  any,
  any,
  Account | Address
>;
