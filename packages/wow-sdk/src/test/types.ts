import {
  Address,
  Chain,
  PublicClient,
  TestClient,
  Transport,
  WalletClient,
} from "viem";
import { SupportedChain } from "../types";

export interface AnvilViemClients {
  walletClient: WalletClient;
  publicClient: PublicClient<Transport, SupportedChain>;
  testClient: TestClient;
  chain: Chain;
}

export interface SimulateContractParametersWithAccount {
  account: Address;
  address: `0x${string}`;
  abi: readonly any[];
  functionName: string;
  args: readonly any[];
  chain?: Chain;
}

export type AnvilForkSettings = {
  forkUrl: string;
  forkBlockNumber: number;
  anvilChainId?: number;
};
