import { describe, expect, vi } from "vitest";
import { parseEther, Address } from "viem";
import { zoraSepolia } from "viem/chains";
import {
  forkUrls,
  makeAnvilTest,
  simulateAndWriteContractWithRetries,
} from "src/anvil";
import { createCollectorClient } from "src/sdk";
import { zoraCreator1155ImplABI } from "@zoralabs/protocol-deployments";
import { SubgraphMintGetter } from "src/mint/subgraph-mint-getter";
import { ERROR_SECONDARY_NOT_STARTED } from "./secondary-client";
import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { mockTimedSaleStrategyTokenQueryResult } from "src/fixtures/mint-query-results";
import { new1155ContractVersion } from "src/create/contract-setup";
import { advanceToSaleAndAndLaunchMarket } from "src/fixtures/secondary";

describe("secondary", () => {
  makeAnvilTest({
    forkBlockNumber: 16072399,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it returns an error when the market is not launched",
    async ({
      viemClients: { publicClient, chain, walletClient, testClient },
    }) => {
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;

      const contractAddress: Address =
        "0xd42557f24034b53e7340a40bb5813ef9ba88f2b4";
      const newTokenId = 4n;
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

      expect(secondaryInfo).toBeDefined();

      expect(secondaryInfo!.minimumMintsForCountdown).toBe(1111n);
      expect(secondaryInfo!.secondaryActivated).toBe(false);

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
    forkBlockNumber: 16072399,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it can buy and sell on secondary when the market is launched",
    async ({
      viemClients: { publicClient, chain, walletClient, testClient },
    }) => {
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;

      const mintGetter = new SubgraphMintGetter(chain.id);
      const contractAddress: Address =
        "0xd42557f24034b53e7340a40bb5813ef9ba88f2b4";
      const newTokenId = 4n;

      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("100"),
      });

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

      const secondaryInfo = await collectorClient.getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
      });

      expect(secondaryInfo).toBeDefined();
      expect(secondaryInfo!.mintCount).toBeGreaterThan(0n);

      // mint 1 less than expected minimum market.
      // make sure that there is no sale end
      const quantityToMintFirst =
        secondaryInfo!.minimumMintsForCountdown! -
        secondaryInfo!.mintCount -
        1n;

      const { parameters: collectParameters } = await collectorClient.mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint: quantityToMintFirst,
        tokenId: newTokenId,
        tokenContract: contractAddress,
      });

      await simulateAndWriteContractWithRetries({
        parameters: collectParameters,
        walletClient,
        publicClient,
      });

      // make sure that there is no sale end
      let saleEnd = (await collectorClient.getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
      }))!.saleEnd;

      expect(saleEnd).toBeUndefined();

      // mint 1 more - this should cause the countdown to start
      const { parameters: collectMoreParameters } = await collectorClient.mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint: 1n,
        tokenId: newTokenId,
        tokenContract: contractAddress,
      });

      await simulateAndWriteContractWithRetries({
        parameters: collectMoreParameters,
        walletClient,
        publicClient,
      });

      // now there should be a sale end
      saleEnd = (await collectorClient.getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
      }))!.saleEnd;

      expect(saleEnd).toBeDefined();

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

      const balanceBefore = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collectorAccount, newTokenId],
      });

      // now get the price ot buy on secondary
      const quantityToBuy = 10n;

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

      expect(balance - balanceBefore).toBe(quantityToBuy);

      // now sell 10_000n tokens
      const quantityToSell = 100n;

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

      expect(balance).toBe(
        quantityToMintFirst + 1n + quantityToBuy - quantityToSell,
      );
    },
    30_000,
  );
});
