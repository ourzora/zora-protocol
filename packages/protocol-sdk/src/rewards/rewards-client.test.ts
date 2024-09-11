import { describe, expect, vi } from "vitest";
import {
  Address,
  Chain,
  encodeAbiParameters,
  erc20Abi,
  parseEther,
  PublicClient,
  WalletClient,
} from "viem";
import { zoraSepolia } from "viem/chains";
import {
  forkUrls,
  makeAnvilTest,
  simulateAndWriteContractWithRetries,
} from "src/anvil";
import { createCollectorClient, createCreatorClient } from "src/sdk";
import {
  demoContractMetadataURI,
  demoTokenMetadataURI,
} from "src/create/1155-create-helper.test";
import { new1155ContractVersion } from "src/create/contract-setup";
import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { SubgraphMintGetter } from "src/mint/subgraph-mint-getter";
import { mockTimedSaleStrategyTokenQueryResult } from "src/fixtures/mint-query-results";
import {
  secondarySwapABI,
  secondarySwapAddress,
  zoraCreator1155ImplABI,
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { makeContractParameters } from "src/utils";
import { SubgraphRewardsGetter } from "./subgraph-rewards-getter";
import { mockRewardsQueryResults } from "src/fixtures/rewards-query-results";

async function setupContractAndToken({
  chain,
  publicClient,
  creatorAccount,
  walletClient,
}: {
  chain: Chain;
  publicClient: PublicClient;
  creatorAccount: Address;
  walletClient: WalletClient;
}) {
  const rewardsGetter = new SubgraphRewardsGetter(chain.id);
  const creatorClient = createCreatorClient({
    chainId: chain.id,
    publicClient,
    rewardsGetter,
  });

  const mintGetter = new SubgraphMintGetter(chain.id);
  // create a new 1155 contract

  const { contractAddress, parameters, newTokenId } =
    await creatorClient.create1155({
      contract: {
        uri: demoContractMetadataURI,
        name: `Test 1155-${Math.round(Math.random() * 100_000_000_000)}`,
      },
      token: {
        tokenMetadataURI: demoTokenMetadataURI,
      },
      account: creatorAccount,
    });

  await simulateAndWriteContractWithRetries({
    parameters,
    walletClient,
    publicClient,
  });

  return {
    creatorClient,
    contractAddress,
    newTokenId,
    mintGetter,
    rewardsGetter,
  };
}

describe("rewardsClient", () => {
  makeAnvilTest({
    forkBlockNumber: 13914833,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it can view and withdraw rewards for mints",
    async ({
      viemClients: { publicClient, chain, walletClient, testClient },
    }) => {
      const creatorAccount = (await walletClient.getAddresses()!)[0]!;
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;

      const { creatorClient, contractAddress, newTokenId, mintGetter } =
        await setupContractAndToken({
          chain,
          publicClient,
          creatorAccount,
          walletClient,
        });

      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("10"),
      });

      const quantityToMint = 10n;

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

      const rewardsBalance = await creatorClient.getRewardsBalances({
        account: creatorAccount,
      });

      // creator reward is
      const expectedRewardsBalance = quantityToMint * parseEther("0.0000555");

      expect(rewardsBalance.protocolRewards).toEqual(expectedRewardsBalance);

      const beforeBalance = await publicClient.getBalance({
        address: creatorAccount,
      });

      const { parameters: withdrawParams } =
        await creatorClient.withdrawRewards({
          account: collectorAccount,
          withdrawFor: creatorAccount,
          claimSecondaryRoyalties: false,
        });

      await simulateAndWriteContractWithRetries({
        parameters: withdrawParams,
        walletClient,
        publicClient,
      });

      const afterBalance = await publicClient.getBalance({
        address: creatorAccount,
      });

      expect(afterBalance - beforeBalance).toBe(expectedRewardsBalance);
    },
    30_000,
  );
  makeAnvilTest({
    forkBlockNumber: 13914833,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it can view and withdraw rewards and secondary royalties for mints",
    async ({
      viemClients: { publicClient, chain, walletClient, testClient },
    }) => {
      const creatorAccount = (await walletClient.getAddresses()!)[0]!;
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;

      const {
        creatorClient,
        contractAddress,
        newTokenId,
        mintGetter,
        rewardsGetter,
      } = await setupContractAndToken({
        chain,
        publicClient,
        creatorAccount,
        walletClient,
      });

      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("100"),
      });

      const quantityToMint = 10_000n;

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

      const saleEnd = (
        await publicClient.readContract({
          abi: zoraTimedSaleStrategyABI,
          address:
            zoraTimedSaleStrategyAddress[
              chain.id as keyof typeof zoraTimedSaleStrategyAddress
            ],
          functionName: "saleV2",
          args: [contractAddress, newTokenId],
        })
      ).saleEnd;

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
          args: [contractAddress, newTokenId],
          address:
            zoraTimedSaleStrategyAddress[
              chain.id as keyof typeof zoraTimedSaleStrategyAddress
            ],
          account: collectorAccount,
        }),
        publicClient,
        walletClient,
      });

      const erc20z = (
        await publicClient.readContract({
          abi: zoraTimedSaleStrategyABI,
          address:
            zoraTimedSaleStrategyAddress[
              chain.id as keyof typeof zoraTimedSaleStrategyAddress
            ],
          functionName: "sale",
          args: [contractAddress, newTokenId],
        })
      ).erc20zAddress;

      // after market is launched, by 100 from the pool.  there should be some rewards
      // balances from secondary royalties
      await simulateAndWriteContractWithRetries({
        parameters: makeContractParameters({
          abi: secondarySwapABI,
          address:
            secondarySwapAddress[chain.id as keyof typeof secondarySwapAddress],
          functionName: "buy1155",
          args: [
            erc20z,
            100n,
            collectorAccount,
            collectorAccount,
            parseEther("1"),
            0n,
          ],
          account: collectorAccount,
          value: parseEther("1"),
        }),
        walletClient,
        publicClient,
      });

      const abiParameters = [
        { name: "recipient", internalType: "address payable", type: "address" },
        { name: "minEthToAcquire", internalType: "uint256", type: "uint256" },
        { name: "sqrtPriceLimitX96", internalType: "uint160", type: "uint160" },
      ] as const;
      const sellData = encodeAbiParameters(abiParameters, [
        collectorAccount,
        0n,
        0n,
      ]);
      await simulateAndWriteContractWithRetries({
        parameters: makeContractParameters({
          functionName: "safeTransferFrom",
          address: contractAddress,
          abi: zoraCreator1155ImplABI,
          account: collectorAccount,
          args: [
            collectorAccount,
            secondarySwapAddress[chain.id as keyof typeof secondarySwapAddress],
            newTokenId,
            100n,
            sellData,
          ],
        }),
        walletClient,
        publicClient,
      });

      // now we should be able to get rewards balances for these royalties

      // we need to stub the subgraph return
      rewardsGetter.subgraphQuerier.query = vi
        .fn<ISubgraphQuerier["query"]>()
        .mockResolvedValue(
          mockRewardsQueryResults({
            erc20z: [erc20z],
          }),
        );

      const rewardsBalance = await creatorClient.getRewardsBalances({
        account: creatorAccount,
      });

      expect(rewardsBalance.secondaryRoyalties.eth).toBeGreaterThan(0);
      expect(rewardsBalance.secondaryRoyalties.erc20[erc20z]).toBeGreaterThan(
        0,
      );

      const beforeBalance = await publicClient.getBalance({
        address: creatorAccount,
      });

      // it can withdraw all rewards
      await simulateAndWriteContractWithRetries({
        parameters: (
          await creatorClient.withdrawRewards({
            account: collectorAccount,
            withdrawFor: creatorAccount,
            claimSecondaryRoyalties: true,
          })
        ).parameters,
        publicClient,
        walletClient,
      });

      const afterBalance = await publicClient.getBalance({
        address: creatorAccount,
      });

      // make sure that some additional royalties were withdrawn, this is how we can do greater than
      // we cant get exact precision
      expect(afterBalance - beforeBalance).toBeGreaterThan(
        rewardsBalance.protocolRewards,
      );

      const erc20balance = await publicClient.readContract({
        abi: erc20Abi,
        address: erc20z,
        functionName: "balanceOf",
        args: [creatorAccount],
      });

      expect(erc20balance).toBeGreaterThan(0);
    },
    30_000,
  );
});
