import {
  Account,
  Chain,
  PublicClient,
  TestClient,
  Transport,
  WalletClient,
} from "viem";

export interface AnvilViemClients {
  walletClient: WalletClient;
  publicClient: PublicClient<Transport, Chain>;
  testClient: TestClient;
  chain: Chain;
}

export interface SimulateContractParametersWithAccount {
  account: Account;
  address: `0x${string}`;
  abi: any[];
  functionName: string;
  args: any[];
  chain?: Chain;
}

export type AnvilForkSettings = {
  forkUrl: string;
  forkBlockNumber: number;
  anvilChainId?: number;
};
