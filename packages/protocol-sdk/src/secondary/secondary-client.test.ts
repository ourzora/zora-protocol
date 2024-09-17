import { describe, expect, vi } from "vitest";
import {
  Address,
  parseEther,
  PublicClient,
  TestClient,
  WalletClient,
  Account,
} from "viem";
import { zoraSepolia } from "viem/chains";
import {
  forkUrls,
  makeAnvilTest,
  simulateAndWriteContractWithRetries,
} from "src/anvil";
import { createCollectorClient } from "src/sdk";
import {
  zoraCreator1155ImplABI,
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { makeContractParameters } from "src/utils";
import { setupContractAndToken } from "src/fixtures/contract-setup";
import { CollectorClient } from "src/sdk";
import { ERROR_SECONDARY_NOT_STARTED } from "./secondary-client";
import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { mockTimedSaleStrategyTokenQueryResult } from "src/fixtures/mint-query-results";
import { new1155ContractVersion } from "src/create/contract-setup";

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

describe("secondary", () => {
  makeAnvilTest({
    forkBlockNumber: 13914833,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it returns an error when the market is not launched",
    async ({
      viemClients: { publicClient, chain, walletClient, testClient },
    }) => {
      const creatorAccount = (await walletClient.getAddresses()!)[0]!;
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;

      const { contractAddress, newTokenId } = await setupContractAndToken({
        chain,
        publicClient,
        creatorAccount,
        walletClient,
      });

      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("100"),
      });

      const collectorClient = createCollectorClient({
        chainId: chain.id,
        publicClient,
      });

      const secondaryInfo = await collectorClient.getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
      });

      expect(secondaryInfo?.secondaryActivated).toBe(false);

      const buyResult = await collectorClient.buy1155OnSecondary({
        account: collectorAccount,
        quantity: 100n,
        contract: contractAddress,
        tokenId: newTokenId,
      });

      expect(buyResult.error).toEqual(ERROR_SECONDARY_NOT_STARTED);
    },
    20_000,
  );

  makeAnvilTest({
    forkBlockNumber: 13914833,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it can buy and sell on secondary when the market is launched",
    async ({
      viemClients: { publicClient, chain, walletClient, testClient },
    }) => {
      const creatorAccount = (await walletClient.getAddresses()!)[0]!;
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;

      const { contractAddress, newTokenId, mintGetter } =
        await setupContractAndToken({
          chain,
          publicClient,
          creatorAccount,
          walletClient,
        });

      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("100"),
      });

      const quantityToMint = 100_000n;

      mintGetter.subgraphQuerier.query = vi
        .fn<ISubgraphQuerier["query"]>()
        .mockResolvedValue({
          zoraCreateToken: mockTimedSaleStrategyTokenQueryResult({
            chainId: chain.id,
            tokenId: newTokenId,
            contractAddress,
            contractVersion:
              new1155ContractVersion[
                chain.id as keyof typeof new1155ContractVersion
              ],
          }),
        });

      const collectorClient = createCollectorClient({
        chainId: chain.id,
        publicClient,
        mintGetter,
      });

      const { parameters: collectParameters } = await collectorClient.mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint,
        tokenId: newTokenId,
        tokenContract: contractAddress,
      });

      await simulateAndWriteContractWithRetries({
        parameters: collectParameters,
        walletClient,
        publicClient,
      });

      await advanceToSaleAndAndLaunchMarket({
        contractAddress,
        tokenId: newTokenId,
        testClient,
        publicClient,
        walletClient,
        collectorClient,
        chainId: chain.id,
        account: collectorAccount,
      });

      // now get the price ot buy on secondary
      const quantityToBuy = 1000n;

      const buyResult = await collectorClient.buy1155OnSecondary({
        account: collectorAccount,
        quantity: quantityToBuy,
        contract: contractAddress,
        tokenId: newTokenId,
      });

      expect(buyResult.error).toBeUndefined();

      expect(buyResult.price!.wei.perToken).toBeGreaterThan(
        parseEther("0.000111"),
      );

      // expected amount with slippage is total price * 1.005 considering bigint:
      const expectedTotalWithSlippage =
        buyResult.price!.wei.total + (buyResult.price!.wei.total * 5n) / 1000n;

      expect(buyResult.parameters!.value).toBe(expectedTotalWithSlippage);

      // execute the buy
      await simulateAndWriteContractWithRetries({
        parameters: buyResult.parameters!,
        walletClient,
        publicClient,
      });

      // now get balance of erc1155, should be minted by quantity bought
      let balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, newTokenId],
      });

      expect(balance).toBe(quantityToBuy + quantityToMint);

      // now sell 10_000n tokens
      const quantityToSell = 10_000n;

      const sellResult = await collectorClient.sell1155OnSecondary({
        account: collectorAccount,
        quantity: quantityToSell,
        contract: contractAddress,
        tokenId: newTokenId,
      });

      expect(sellResult.error).toBeUndefined();

      expect(sellResult.price!.wei.perToken).toBeLessThan(
        parseEther("0.000111"),
      );

      // execute the sell
      await simulateAndWriteContractWithRetries({
        parameters: sellResult.parameters!,
        walletClient,
        publicClient,
      });

      // now get balance of erc1155, should be minted by quantity bought
      balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, newTokenId],
      });

      expect(balance).toBe(quantityToMint + quantityToBuy - quantityToSell);
    },
    30_000,
  );
});
