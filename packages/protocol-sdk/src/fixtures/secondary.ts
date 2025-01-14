import {
  Address,
  Account,
  PublicClient,
  TestClient,
  WalletClient,
  Transport,
  Chain,
} from "viem";
import { simulateAndWriteContractWithRetries } from "../test-utils";
import { makeContractParameters } from "../utils";
import {
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { getSecondaryInfo } from "src/secondary/utils";
export async function advanceToSaleAndAndLaunchMarket({
  contractAddress,
  tokenId,
  testClient,
  publicClient,
  walletClient,
  account,
}: {
  contractAddress: Address;
  tokenId: bigint;
  testClient: TestClient;
  publicClient: PublicClient<Transport, Chain>;
  walletClient: WalletClient;
  account: Address | Account;
}) {
  const saleInfo = await getSecondaryInfo({
    contract: contractAddress,
    tokenId,
    publicClient,
  });

  if (!saleInfo) {
    throw new Error("Sale not set");
  }

  if (!saleInfo.saleEnd) {
    throw new Error("Sale end not set");
  }

  const saleEnd = saleInfo.saleEnd;

  // advance to end of sale
  await testClient.setNextBlockTimestamp({
    timestamp: saleEnd,
  });

  await testClient.mine({
    blocks: 1,
  });

  const chainId = publicClient.chain.id;

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
