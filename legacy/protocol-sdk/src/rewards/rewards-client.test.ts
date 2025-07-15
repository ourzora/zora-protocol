import { describe, expect, vi } from "vitest";
import { encodeAbiParameters, erc20Abi, parseEther } from "viem";
import { zoraSepolia, base } from "viem/chains";
import { forkUrls, makeAnvilTest } from "src/anvil";
import { simulateAndWriteContractWithRetries } from "src/test-utils";
import { new1155ContractVersion } from "src/create/contract-setup";
import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { mockTimedSaleStrategyTokenQueryResult } from "src/fixtures/mint-query-results";
import {
  secondarySwapABI,
  secondarySwapAddress,
  zoraCreator1155ImplABI,
} from "@zoralabs/protocol-deployments";
import { makeContractParameters } from "src/utils";
import { setupContractAndToken } from "src/fixtures/contract-setup";
import { advanceToSaleAndAndLaunchMarket } from "src/fixtures/secondary";
import { CreatorERC20zQueryResult } from "./subgraph-queries";
import { getRewardsBalances } from "./rewards-queries";
import { mint } from "src/mint/mint-client";
import { getSecondaryInfo } from "src/secondary/utils";

describe("rewardsClient", () => {
  makeAnvilTest({
    forkBlockNumber: 22375202,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "it can query rewards balances where there are multiple minters",
    async ({ viemClients: { publicClient } }) => {
      const rewardsBalance = await getRewardsBalances({
        account: "0x129F04B140Acc1AA350be2F9f048C178103c62f3",
        publicClient,
      });

      const erc20zKeys = Object.keys(rewardsBalance.secondaryRoyalties.erc20);

      expect(erc20zKeys.length).toBeGreaterThan(0);
    },
    20_000,
  );
  makeAnvilTest({
    forkBlockNumber: 14653556,
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

      const { parameters: collectParameters } = await mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint,
        tokenId: newTokenId,
        tokenContract: contractAddress,
        publicClient,
        mintGetter,
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
    forkBlockNumber: 17938475,
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

      const quantityToMint = 1111n;

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

      const { parameters: collectParameters } = await mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint,
        tokenId: newTokenId,
        tokenContract: contractAddress,
        publicClient,
        mintGetter,
      });

      await simulateAndWriteContractWithRetries({
        parameters: collectParameters,
        walletClient,
        publicClient,
      });

      await advanceToSaleAndAndLaunchMarket({
        account: collectorAccount,
        publicClient,
        walletClient,
        testClient,
        contractAddress,
        tokenId: newTokenId,
      });

      const erc20z = (await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      }))!.erc20z!;

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

      const mockResult: CreatorERC20zQueryResult = {
        zoraCreateTokens: [
          {
            salesStrategies: [
              {
                zoraTimedMinter: {
                  erc20Z: { id: erc20z },
                },
              },
            ],
          },
        ],
      };

      // we need to stub the subgraph return
      rewardsGetter.subgraphQuerier.query = vi
        .fn<ISubgraphQuerier["query"]>()
        .mockResolvedValue(mockResult);

      const rewardsBalance = await creatorClient.getRewardsBalances({
        account: creatorAccount,
      });

      expect(rewardsBalance.protocolRewards).toBeGreaterThan(0n);
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
  makeAnvilTest({
    forkBlockNumber: 17938475,
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

      const quantityToMint = 1111n;

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

      const { parameters: collectParameters } = await mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint,
        tokenId: newTokenId,
        tokenContract: contractAddress,
        publicClient,
        mintGetter,
      });

      await simulateAndWriteContractWithRetries({
        parameters: collectParameters,
        walletClient,
        publicClient,
      });

      await advanceToSaleAndAndLaunchMarket({
        account: collectorAccount,
        publicClient,
        walletClient,
        testClient,
        contractAddress,
        tokenId: newTokenId,
      });

      const erc20z = (await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      }))!.erc20z!;

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

      const mockResult: CreatorERC20zQueryResult = {
        zoraCreateTokens: [
          {
            salesStrategies: [
              {
                zoraTimedMinter: {
                  erc20Z: { id: erc20z },
                },
              },
            ],
          },
        ],
      };

      // we need to stub the subgraph return
      rewardsGetter.subgraphQuerier.query = vi
        .fn<ISubgraphQuerier["query"]>()
        .mockResolvedValue(mockResult);

      const rewardsBalance = await creatorClient.getRewardsBalances({
        account: creatorAccount,
      });

      expect(rewardsBalance.protocolRewards).toBeGreaterThan(0n);
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
  makeAnvilTest({
    forkBlockNumber: 17938475,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it can view and withdraw rewards and secondary royalties for mints when secondary market is not activated yet",
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

      const quantityToMint = 1111n;

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

      const { parameters: collectParameters } = await mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint,
        tokenId: newTokenId,
        tokenContract: contractAddress,
        publicClient,
        mintGetter,
      });

      await simulateAndWriteContractWithRetries({
        parameters: collectParameters,
        walletClient,
        publicClient,
      });

      const erc20z = (await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      }))!.erc20z!;

      // now we should be able to get query rewards balances without any errors
      // even though secondary market is not activated yet

      const mockResult: CreatorERC20zQueryResult = {
        zoraCreateTokens: [
          {
            salesStrategies: [
              {
                zoraTimedMinter: {
                  erc20Z: { id: erc20z },
                },
              },
            ],
          },
        ],
      };

      // we need to stub the subgraph return
      rewardsGetter.subgraphQuerier.query = vi
        .fn<ISubgraphQuerier["query"]>()
        .mockResolvedValue(mockResult);

      const rewardsBalance = await creatorClient.getRewardsBalances({
        account: creatorAccount,
      });

      expect(rewardsBalance.protocolRewards).toBeGreaterThan(0n);
      expect(rewardsBalance.secondaryRoyalties.erc20[erc20z]).toBeUndefined();

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
    },
    30_000,
  );
});
