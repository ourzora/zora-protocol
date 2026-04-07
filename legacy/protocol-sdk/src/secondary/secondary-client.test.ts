import { describe, expect, vi } from "vitest";
import { parseEther, Address, parseEventLogs } from "viem";
import { zoraSepolia } from "viem/chains";
import { forkUrls, makeAnvilTest } from "src/anvil";
import { simulateAndWriteContractWithRetries } from "src/test-utils";
import {
  zoraCreator1155ImplABI,
  commentsABI,
  callerAndCommenterABI,
  PermitBuyOnSecondaryAndComment,
  permitBuyOnSecondaryAndCommentTypedDataDefinition,
  callerAndCommenterAddress,
  sparkValue,
} from "@zoralabs/protocol-deployments";
import { SubgraphMintGetter } from "src/mint/subgraph-mint-getter";
import {
  buy1155OnSecondary,
  ERROR_SECONDARY_NOT_STARTED,
  sell1155OnSecondary,
} from "./secondary-client";
import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { mockTimedSaleStrategyTokenQueryResult } from "src/fixtures/mint-query-results";
import { new1155ContractVersion } from "src/create/contract-setup";
import { advanceToSaleAndAndLaunchMarket } from "src/fixtures/secondary";
import { randomNonce } from "src/test-utils";
import { getSecondaryInfo } from "./utils";
import { mint } from "src/mint/mint-client";

describe("secondary", () => {
  makeAnvilTest({
    forkBlockNumber: 16072399,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it returns an error when the market is not launched",
    async ({ viemClients: { publicClient, walletClient, testClient } }) => {
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;

      const contractAddress: Address =
        "0xd42557f24034b53e7340a40bb5813ef9ba88f2b4";
      const newTokenId = 4n;
      await testClient.setBalance({
        address: collectorAccount,
        value: parseEther("100"),
      });

      const secondaryInfo = await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      });

      expect(secondaryInfo).toBeDefined();

      expect(secondaryInfo!.minimumMintsForCountdown).toBe(1111n);
      expect(secondaryInfo!.secondaryActivated).toBe(false);

      const buyResult = await buy1155OnSecondary({
        account: collectorAccount,
        quantity: 100n,
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
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

      const secondaryInfo = await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      });

      expect(secondaryInfo).toBeDefined();
      expect(secondaryInfo!.mintCount).toBeGreaterThan(0n);

      // mint 1 less than expected minimum market.
      // make sure that there is no sale end
      const quantityToMintFirst =
        secondaryInfo!.minimumMintsForCountdown! -
        secondaryInfo!.mintCount -
        1n;

      const { parameters: collectParameters } = await mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint: quantityToMintFirst,
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

      // make sure that there is no sale end
      let saleEnd = (await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      }))!.saleEnd;

      expect(saleEnd).toBeUndefined();

      // mint 1 more - this should cause the countdown to start
      const { parameters: collectMoreParameters } = await mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint: 1n,
        tokenId: newTokenId,
        tokenContract: contractAddress,
        publicClient,
        mintGetter,
      });

      await simulateAndWriteContractWithRetries({
        parameters: collectMoreParameters,
        walletClient,
        publicClient,
      });

      // now there should be a sale end
      saleEnd = (await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      }))!.saleEnd;

      expect(saleEnd).toBeDefined();

      await advanceToSaleAndAndLaunchMarket({
        contractAddress,
        tokenId: newTokenId,
        testClient,
        publicClient,
        walletClient,
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

      const buyResult = await buy1155OnSecondary({
        account: collectorAccount,
        quantity: quantityToBuy,
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
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

      const sellResult = await sell1155OnSecondary({
        account: collectorAccount,
        quantity: quantityToSell,
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
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

  makeAnvilTest({
    forkBlockNumber: 16339853,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "it can buy on secondary with a comment",
    async ({
      viemClients: { publicClient, chain, walletClient, testClient },
    }) => {
      const collectorAccount = (await walletClient.getAddresses()!)[1]!;
      const executorAccount = (await walletClient.getAddresses()!)[3]!;

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

      const secondaryInfo = await getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      });

      // mint enough to start the countdown
      const quantityToMint =
        secondaryInfo!.minimumMintsForCountdown! - secondaryInfo!.mintCount;

      const { parameters: collectParameters } = await mint({
        minterAccount: collectorAccount,
        mintType: "1155",
        quantityToMint: quantityToMint,
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
        contractAddress,
        tokenId: newTokenId,
        testClient,
        publicClient,
        walletClient,
        account: collectorAccount,
      });

      const buyResult = await buy1155OnSecondary({
        account: collectorAccount,
        quantity: 5n,
        contract: contractAddress,
        tokenId: newTokenId,
        comment: "test comment",
        publicClient,
      });

      const receipt = await simulateAndWriteContractWithRetries({
        parameters: buyResult.parameters!,
        walletClient,
        publicClient,
      });

      const commentedEvent = parseEventLogs({
        abi: commentsABI,
        logs: receipt.logs,
        eventName: "Commented",
      });

      expect(commentedEvent[0]).toBeDefined();
      expect(commentedEvent[0]!.args.text).toBe("test comment");

      const boughtAndCommentedEvent = parseEventLogs({
        abi: callerAndCommenterABI,
        logs: receipt.logs,
        eventName: "SwappedOnSecondaryAndCommented",
      });

      expect(boughtAndCommentedEvent[0]).toBeDefined();
      expect(boughtAndCommentedEvent[0]!.args.comment).toBe("test comment");
      expect(boughtAndCommentedEvent[0]!.args.quantity).toBe(5n);
      expect(boughtAndCommentedEvent[0]!.args.swapDirection).toBe(0);

      // PERMIT BUY TEST
      const buyResultASecondTime = await buy1155OnSecondary({
        account: collectorAccount,
        quantity: 5n,
        contract: contractAddress,
        tokenId: newTokenId,
        comment: "test comment",
        publicClient,
      });

      const valueToSend = (buyResultASecondTime.price!.wei.total * 105n) / 100n;

      const { timestamp } = await publicClient.getBlock();

      const permitBuy: PermitBuyOnSecondaryAndComment = {
        collection: contractAddress,
        tokenId: newTokenId,
        quantity: 5n,
        commenter: collectorAccount,
        comment: "test comment",
        maxEthToSpend: valueToSend,
        deadline: timestamp + 30n,
        sqrtPriceLimitX96: 0n,
        nonce: randomNonce(),
        sourceChainId: chain.id,
        destinationChainId: chain.id,
      };

      const permitBuySignature = await walletClient.signTypedData(
        permitBuyOnSecondaryAndCommentTypedDataDefinition(permitBuy),
      );

      await testClient.setBalance({
        address: executorAccount,
        value: parseEther("1"),
      });

      const { request } = await publicClient.simulateContract({
        abi: callerAndCommenterABI,
        address:
          callerAndCommenterAddress[
            chain.id as keyof typeof callerAndCommenterAddress
          ],
        functionName: "permitBuyOnSecondaryAndComment",
        args: [permitBuy, permitBuySignature],
        value: valueToSend,
        account: executorAccount,
      });

      await simulateAndWriteContractWithRetries({
        parameters: request,
        walletClient,
        publicClient,
      });

      // now PERMIT SELL ON SECONDARY TEST
      const quantityToSell = 3n;

      const sellResult = await sell1155OnSecondary({
        account: collectorAccount,
        quantity: quantityToSell,
        contract: contractAddress,
        tokenId: newTokenId,
        publicClient,
      });

      expect(sellResult.error).toBeUndefined();

      // approve 1155s for callerAndCommenter to transfer, when selling
      await simulateAndWriteContractWithRetries({
        parameters: {
          abi: zoraCreator1155ImplABI,
          address: contractAddress,
          functionName: "setApprovalForAll",
          account: collectorAccount,
          args: [
            callerAndCommenterAddress[
              chain.id as keyof typeof callerAndCommenterAddress
            ],
            true,
          ],
        },
        walletClient,
        publicClient,
      });

      // now sell on secondary with comment
      // by calling the caller and commenter contract
      // if including a comment, must send sparkValue() as value
      // function signature:
      // function sellOnSecondaryAndComment(
      //   address commenter,
      //   uint256 quantity,
      //   address collection,
      //   uint256 tokenId,
      //   address payable recipient,
      //   uint256 minEthToAcquire,
      //   uint160 sqrtPriceLimitX96,
      //   string calldata comment
      // )
      await simulateAndWriteContractWithRetries({
        parameters: {
          abi: callerAndCommenterABI,
          address:
            callerAndCommenterAddress[
              chain.id as keyof typeof callerAndCommenterAddress
            ],
          functionName: "sellOnSecondaryAndComment",
          account: collectorAccount,
          args: [
            collectorAccount,
            quantityToSell,
            contractAddress,
            newTokenId,
            collectorAccount,
            // sell result with slippage
            (sellResult.price!.wei.total * 95n) / 100n,
            0n,
            "test comment",
          ],
          value: sparkValue(),
        },
        walletClient,
        publicClient,
      });
    },
    20_000,
  );
});
