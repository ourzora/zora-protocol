import { Address, Account, PublicClient, TestClient, WalletClient } from "viem";
import { CollectorClient } from "../sdk";
import { simulateAndWriteContractWithRetries } from "../anvil";
import { makeContractParameters } from "../utils";
import {
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";

export async function advanceToSaleAndAndLaunchMarket({
  contractAddress,
  tokenId,
  testClient,
  publicClient,
  walletClient,
  collectorClient,
  chainId,
  account,
}: {
  contractAddress: Address;
  tokenId: bigint;
  testClient: TestClient;
  publicClient: PublicClient;
  walletClient: WalletClient;
  collectorClient: CollectorClient;
  chainId: number;
  account: Address | Account;
}) {
  const saleEnd = (await collectorClient.getSecondaryInfo({
    contract: contractAddress,
    tokenId,
  }))!.saleEnd!;

  // advance to end of sale
  await testClient.setNextBlockTimestamp({
    timestamp: saleEnd,
  });

  await testClient.mine({
    blocks: 1,
  });

  // advance to end of sale
  // launch the market
  await simulateAndWriteContractWithRetries({
    parameters: makeContractParameters({
      abi: zoraTimedSaleStrategyABI,
      functionName: "launchMarket",
      args: [contractAddress, tokenId],
      address:
        zoraTimedSaleStrategyAddress[
          chainId as keyof typeof zoraTimedSaleStrategyAddress
        ],
      account: account,
    }),
    publicClient,
    walletClient,
  });
}
