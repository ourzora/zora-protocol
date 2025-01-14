import { describe, expect, vi } from "vitest";
import {
  Address,
  erc20Abi,
  parseAbi,
  parseEther,
  TransactionReceipt,
  parseEventLogs,
} from "viem";
import { zora, zoraSepolia } from "viem/chains";
import {
  zoraCreator1155ImplABI,
  CommentIdentifier,
  commentsABI,
  callerAndCommenterABI,
} from "@zoralabs/protocol-deployments";
import { forkUrls, makeAnvilTest } from "src/anvil";
import { writeContractWithRetries } from "src/test-utils";
import { getAllowListEntry } from "src/allow-list/allow-list-client";
import { SubgraphMintGetter } from "./subgraph-mint-getter";
import { new1155ContractVersion } from "src/create/contract-setup";
import {
  demoContractMetadataURI,
  demoTokenMetadataURI,
} from "src/fixtures/contract-setup";
import { ISubgraphQuerier } from "src/apis/subgraph-querier";
import { mockTimedSaleStrategyTokenQueryResult } from "src/fixtures/mint-query-results";
import { getToken, getTokensOfContract } from "./mint-queries";
import { create1155 } from "src/create/create-client";

const erc721ABI = parseAbi([
  "function balanceOf(address owner) public view returns (uint256)",
] as const);

const getCommentIdentifierFromReceipt = (
  receipt: TransactionReceipt,
): CommentIdentifier => {
  const logs = parseEventLogs({
    abi: commentsABI,
    logs: receipt.logs,
    eventName: "Commented",
  });

  if (logs.length === 0) {
    throw new Error("No Commented event found in receipt");
  }

  return logs[0]!.args.commentIdentifier;
};

describe("mint-client", () => {
  makeAnvilTest({
    forkBlockNumber: 16028124,
    forkUrl: forkUrls.zoraSepolia,
    anvilChainId: zoraSepolia.id,
  })(
    "mints a new 1155 token with a comment",
    async ({ viemClients }) => {
      const { testClient, walletClient, publicClient } = viemClients;
      const creatorAccount = (await walletClient.getAddresses())[0]!;
      await testClient.setBalance({
        address: creatorAccount,
        value: parseEther("2000"),
      });
      const targetContract: Address =
        "0xD42557F24034b53e7340A40bb5813eF9Ba88F2b4";
      const targetTokenId = 3n;

      const { prepareMint, primaryMintActive } = await getToken({
        tokenContract: targetContract,
        mintType: "1155",
        tokenId: targetTokenId,
        publicClient,
      });

      expect(primaryMintActive).toBe(true);
      expect(prepareMint).toBeDefined();

      const quantityToMint = 5n;

      const { parameters, costs } = prepareMint!({
        minterAccount: creatorAccount,
        quantityToMint,
        mintComment: "This is a fun comment :)",
      });

      expect(costs.totalCostEth).toBe(quantityToMint * parseEther("0.000111"));

      const oldBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount, targetTokenId],
      });

      const simulationResult = await publicClient.simulateContract(parameters);

      const hash = await walletClient.writeContract(simulationResult.request);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const newBalance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount, targetTokenId],
      });
      expect(receipt).to.not.be.null;
      expect(oldBalance).to.be.equal(0n);
      expect(newBalance).to.be.equal(quantityToMint);

      // search for the Commented event in the logs
      const commentIdentifier = getCommentIdentifierFromReceipt(receipt);

      expect(commentIdentifier).toBeDefined();

      const logs = parseEventLogs({
        abi: callerAndCommenterABI,
        logs: receipt.logs,
        eventName: "MintedAndCommented",
      });

      expect(logs.length).toBe(1);
    },
    12 * 1000,
  );

  makeAnvilTest({
    forkUrl: forkUrls.zoraMainnet,
    forkBlockNumber: 6133407,
    anvilChainId: zora.id,
  })(
    "mints a new 721 token",
    async ({ viemClients }) => {
      const { testClient, walletClient, publicClient } = viemClients;
      const creatorAccount = (await walletClient.getAddresses())[0]!;
      await testClient.setBalance({
        address: creatorAccount,
        value: parseEther("2000"),
      });

      const targetContract: Address =
        "0x7aae7e67515A2CbB8585C707Ca6db37BDd3EA839";

      const { prepareMint, primaryMintActive } = await getToken({
        tokenContract: targetContract,
        mintType: "721",
        publicClient,
        preferredSaleType: "fixedPrice",
      });

      const quantityToMint = 3n;

      expect(primaryMintActive).toBe(true);

      const { parameters, costs } = prepareMint!({
        minterAccount: creatorAccount,
        mintRecipient: creatorAccount,
        quantityToMint,
      });

      expect(costs.totalPurchaseCost).toBe(quantityToMint * parseEther("0.08"));
      expect(costs.totalCostEth).toBe(
        quantityToMint * (parseEther("0.08") + parseEther("0.000777")),
      );

      const oldBalance = await publicClient.readContract({
        abi: erc721ABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount],
      });

      const simulated = await publicClient.simulateContract(parameters);

      const hash = await walletClient.writeContract(simulated.request);

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      expect(receipt).not.to.be.null;

      const newBalance = await publicClient.readContract({
        abi: erc721ABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [creatorAccount],
      });

      expect(oldBalance).to.be.equal(0n);
      expect(newBalance).to.be.equal(quantityToMint);
    },
    12 * 1000,
  );

  makeAnvilTest({
    forkUrl: forkUrls.zoraMainnet,
    forkBlockNumber: 14484183,
    anvilChainId: zora.id,
  })(
    "mints an 1155 token with an ERC20 token",
    async ({ viemClients }) => {
      const { testClient, walletClient, publicClient } = viemClients;

      const targetContract: Address =
        "0x689bc305456c38656856d12469aed282fbd89fe0";
      const targetTokenId = 16n;

      const mockCollector = "0xb6b701878a1f80197dF2c209D0BDd292EA73164D";
      await testClient.impersonateAccount({
        address: mockCollector,
      });

      const { prepareMint, primaryMintActive } = await getToken({
        mintType: "1155",
        tokenContract: targetContract,
        tokenId: targetTokenId,
        publicClient,
      });

      const quantityToMint = 1n;

      expect(primaryMintActive).toBe(true);
      expect(prepareMint).toBeDefined();

      const { parameters, erc20Approval, costs } = prepareMint!({
        minterAccount: mockCollector,
        quantityToMint,
      });

      expect(erc20Approval).toBeDefined();
      expect(costs.totalCostEth).toBe(0n);
      expect(costs.totalPurchaseCost).toBe(
        quantityToMint * 1000000000000000000n,
      );
      expect(costs.totalPurchaseCostCurrency).toBe(
        "0xa6b280b42cb0b7c4a4f789ec6ccc3a7609a1bc39",
      );

      const beforeERC20Balance = await publicClient.readContract({
        abi: erc20Abi,
        address: erc20Approval!.erc20,
        functionName: "balanceOf",
        args: [mockCollector],
      });

      // execute the erc20 approval
      const { request: erc20Request } = await publicClient.simulateContract({
        abi: erc20Abi,
        address: erc20Approval!.erc20,
        functionName: "approve",
        args: [erc20Approval!.approveTo, erc20Approval!.quantity],
        account: mockCollector,
      });

      const approveHash = await walletClient.writeContract(erc20Request);
      await publicClient.waitForTransactionReceipt({
        hash: approveHash,
      });

      const beforeCollector1155Balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [mockCollector, targetTokenId],
      });
      expect(beforeCollector1155Balance).to.be.equal(0n);

      // execute the mint
      const simulationResult = await publicClient.simulateContract(parameters);
      const hash = await walletClient.writeContract(simulationResult.request);
      await publicClient.waitForTransactionReceipt({ hash });

      const afterERC20Balance = await publicClient.readContract({
        abi: erc20Abi,
        address: erc20Approval!.erc20,
        functionName: "balanceOf",
        args: [mockCollector],
      });

      expect(beforeERC20Balance - afterERC20Balance).to.be.equal(
        erc20Approval!.quantity,
      );

      const afterCollector1155Balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: targetContract,
        functionName: "balanceOf",
        args: [mockCollector, targetTokenId],
      });
      expect(afterCollector1155Balance).to.be.equal(quantityToMint);
    },
    12 * 1000,
  );

  makeAnvilTest({
    forkUrl: forkUrls.zoraSepolia,
    forkBlockNumber: 10970943,
    anvilChainId: zoraSepolia.id,
  })("can mint allowlist tokens", async ({ viemClients }) => {
    const { publicClient, testClient, walletClient } = viemClients;

    const targetContract = "0x440cF6a9f12b2f05Ec4Cee8eE0F317B0eC0c2eCD";

    const tokenId = 1n;

    const allowListUser = "0xf69fEc6d858c77e969509843852178bd24CAd2B6";
    const merkleRoot =
      "4d08ab87f97dda8811b4bb32a16a175db65e4c140797c993679a3d58aaadc791";

    const allowListEntryResult = await getAllowListEntry({
      address: allowListUser,
      merkleRoot,
    });

    const { prepareMint, primaryMintActive } = await getToken({
      mintType: "1155",
      tokenContract: targetContract,
      tokenId,
      publicClient,
    });

    const minter = (await walletClient.getAddresses())[0]!;

    expect(primaryMintActive).toBe(true);

    await testClient.setBalance({
      address: minter,
      value: parseEther("10"),
    });

    const quantityToMint = allowListEntryResult.allowListEntry!.maxCanMint;

    const { parameters } = prepareMint!({
      minterAccount: minter,
      quantityToMint,
      mintRecipient: allowListUser,
      allowListEntry: allowListEntryResult.allowListEntry,
    });

    const { request } = await publicClient.simulateContract(parameters);
    const hash = await walletClient.writeContract(request);

    await publicClient.waitForTransactionReceipt({ hash });

    const balance = await publicClient.readContract({
      abi: zoraCreator1155ImplABI,
      functionName: "balanceOf",
      address: targetContract,
      args: [allowListUser, tokenId],
    });

    expect(balance).toBe(BigInt(quantityToMint));
  }),
    makeAnvilTest({
      forkUrl: forkUrls.zoraSepolia,
      forkBlockNumber: 10294670,
      anvilChainId: zoraSepolia.id,
    })(
      "gets onchain and premint mintables",
      async ({ viemClients }) => {
        const { publicClient } = viemClients;

        const targetContract: Address =
          "0xa33e4228843092bb0f2fcbb2eb237bcefc1046b3";

        const { tokens: mintables, contract } = await getTokensOfContract({
          tokenContract: targetContract,
          publicClient,
        });

        expect(mintables.length).toBe(4);
        expect(contract).toBeDefined();
      },
      12 * 1000,
    );

  makeAnvilTest({
    forkUrl: forkUrls.zoraMainnet,
    forkBlockNumber: 19000000,
    anvilChainId: zora.id,
  })(
    "can mint a zora timed sale strategy mint",
    async ({ viemClients }) => {
      const { publicClient, chain, walletClient } = viemClients;

      const creator = (await walletClient.getAddresses())[0]!;

      const { parameters, contractAddress, newTokenId } = await create1155({
        account: creator,
        contract: {
          name: "Test Timed Sale",
          uri: demoContractMetadataURI,
          defaultAdmin: creator,
        },
        token: {
          tokenMetadataURI: demoTokenMetadataURI,
        },
        publicClient,
      });

      const { request: createRequest } =
        await publicClient.simulateContract(parameters);
      await writeContractWithRetries({
        request: createRequest,
        walletClient,
        publicClient,
      });

      const saleEnd =
        BigInt(Math.round(new Date().getTime() / 1000)) + 1000000n;
      const zoraCreateToken = mockTimedSaleStrategyTokenQueryResult({
        chainId: chain.id,
        contractAddress,
        contractVersion:
          new1155ContractVersion[
            chain.id as keyof typeof new1155ContractVersion
          ],
        tokenId: newTokenId,
        saleEnd,
      });

      const mockQuery = vi.fn<ISubgraphQuerier["query"]>().mockResolvedValue({
        zoraCreateToken,
      });

      const mintGetter = new SubgraphMintGetter(chain.id);
      mintGetter.subgraphQuerier.query = mockQuery;

      const collector = (await walletClient.getAddresses())[1]!;

      const {
        prepareMint,
        primaryMintActive,
        primaryMintEnd,
        secondaryMarketActive,
      } = await getToken({
        mintType: "1155",
        tokenContract: contractAddress,
        tokenId: newTokenId,
        publicClient,
        mintGetter,
      });

      expect(primaryMintActive).toBe(true);
      expect(secondaryMarketActive).toBe(false);
      expect(primaryMintEnd).toBe(saleEnd);

      const quantityToMint = 10n;

      const { parameters: mintParameters, costs } = prepareMint!({
        minterAccount: collector,
        quantityToMint,
      });

      expect(costs.totalCostEth).toBe(quantityToMint * parseEther("0.000111"));

      const { request: mintRequest } =
        await publicClient.simulateContract(mintParameters);
      const mintHash = await walletClient.writeContract(mintRequest);
      const mintReceipt = await publicClient.waitForTransactionReceipt({
        hash: mintHash,
      });
      expect(mintReceipt.status).toBe("success");

      const balance = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "balanceOf",
        args: [collector, newTokenId],
      });

      expect(balance).toBe(quantityToMint);
    },
    20_000,
  );
});
