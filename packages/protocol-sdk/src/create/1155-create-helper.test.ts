import { describe, expect, vi } from "vitest";
import {
  getContractAddressFromReceipt,
  getTokenIdFromCreateReceipt,
} from "./1155-create-helper";
import { createCollectorClient, createCreatorClient } from "src/sdk";
import {
  zoraCreator1155ImplABI,
  zoraTimedSaleStrategyABI,
  zoraTimedSaleStrategyAddress,
} from "@zoralabs/protocol-deployments";
import { waitForSuccess } from "src/test-utils";
import { Address, erc20Abi, parseEther, PublicClient } from "viem";
import { makePrepareMint1155TokenParams } from "src/mint/mint-transactions";
import {
  forkUrls,
  makeAnvilTest,
  simulateAndWriteContractWithRetries,
  writeContractWithRetries,
} from "src/anvil";
import { zora } from "viem/chains";
import { AllowList } from "src/allow-list/types";
import { createAllowList } from "src/allow-list/allow-list-client";
import { SubgraphContractGetter } from "./contract-getter";
import {
  DEFAULT_MINIMUM_MARKET_ETH,
  DEFAULT_MARKET_COUNTDOWN,
} from "./minter-defaults";
import { randomNewContract } from "src/test-utils";
import { demoTokenMetadataURI } from "src/fixtures/contract-setup";

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraMainnet,
  forkBlockNumber: 19000000,
  anvilChainId: zora.id,
});

const PERMISSION_BITS = {
  MINTER: 2n ** 2n,
};

const minterIsMinterOnToken = async ({
  publicClient,
  contractAddress,
  tokenId,
  minter,
}: {
  publicClient: Pick<PublicClient, "readContract">;
  contractAddress: Address;
  tokenId: bigint;
  minter: Address;
}) => {
  return await publicClient.readContract({
    abi: zoraCreator1155ImplABI,
    address: contractAddress,
    functionName: "isAdminOrRole",
    args: [minter, tokenId, PERMISSION_BITS.MINTER],
  });
};

describe("create-helper", () => {
  anvilTest(
    "when no sales config is provided, it creates a new 1155 contract and token using the timed sale strategy",
    async ({ viemClients: { publicClient, walletClient, chain } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
      });

      const saleStart = 5n;
      const contract = randomNewContract();
      const {
        parameters: parameters,
        contractAddress,
        newTokenId,
      } = await creatorClient.create1155({
        contract,
        token: {
          tokenMetadataURI: demoTokenMetadataURI,
          mintToCreatorCount: 1,
          salesConfig: {
            saleStart,
            type: "timed",
          },
        },
        account: creatorAddress,
      });

      const { request } = await publicClient.simulateContract(parameters);
      const receipt = await writeContractWithRetries({
        request,
        walletClient,
        publicClient,
      });
      expect(receipt).not.toBeNull();
      expect(receipt.to?.toLowerCase()).to.equal(
        "0x777777c338d93e2c7adf08d102d45ca7cc4ed021".toLowerCase(),
      );
      expect(getTokenIdFromCreateReceipt(receipt)).to.be.equal(1n);
      expect(getContractAddressFromReceipt(receipt)).to.be.equal(
        contractAddress,
      );

      const salesConfig = await publicClient.readContract({
        abi: zoraTimedSaleStrategyABI,
        address:
          zoraTimedSaleStrategyAddress[
            chain.id as keyof typeof zoraTimedSaleStrategyAddress
          ],
        functionName: "saleV2",
        args: [contractAddress, newTokenId],
      });

      expect(salesConfig.saleEnd).toBe(0n);
      expect(salesConfig.saleStart).toBe(saleStart);
      expect(salesConfig.minimumMarketEth).toBe(DEFAULT_MINIMUM_MARKET_ETH);
      expect(salesConfig.marketCountdown).toBe(DEFAULT_MARKET_COUNTDOWN);

      const erc20Name = await publicClient.readContract({
        abi: erc20Abi,
        address: salesConfig.erc20zAddress,
        functionName: "name",
      });

      expect(erc20Name).toBe(contract.name);

      expect(
        await minterIsMinterOnToken({
          contractAddress,
          tokenId: newTokenId,
          publicClient,
          minter:
            zoraTimedSaleStrategyAddress[
              chain.id as keyof typeof zoraTimedSaleStrategyAddress
            ],
        }),
      ).toBe(true);

      // get secondary info, minimum mints count should be 1111, sale end should be undefined,
      // market countdown should be 24 hours

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
      expect(secondaryInfo!.saleEnd).toBeUndefined();
      expect(secondaryInfo!.marketCountdown).toBe(24n * 60n * 60n);
    },
    20 * 1000,
  );
  anvilTest(
    "when minimumMintsForCountdown is set, it uses that as the minimum mints for countdown",
    async ({ viemClients: { publicClient, walletClient, chain } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
      });

      const saleStart = 5n;
      const contract = randomNewContract();
      const { parameters, contractAddress, newTokenId } =
        await creatorClient.create1155({
          contract,
          token: {
            tokenMetadataURI: demoTokenMetadataURI,
            mintToCreatorCount: 1,
            salesConfig: {
              saleStart,
              minimumMintsForCountdown: 500n,
              marketCountdown: 100n,
              type: "timed",
            },
          },
          account: creatorAddress,
        });

      await simulateAndWriteContractWithRetries({
        parameters,
        walletClient,
        publicClient,
      });

      const secondaryInfo = await createCollectorClient({
        chainId: chain.id,
        publicClient,
      }).getSecondaryInfo({
        contract: contractAddress,
        tokenId: newTokenId,
      });

      expect(secondaryInfo).toBeDefined();
      expect(secondaryInfo!.minimumMintsForCountdown).toBe(500n);
      expect(secondaryInfo!.marketCountdown).toBe(100n);
    },
    20 * 1000,
  );
  anvilTest(
    "when price is set to 0, it creates a new 1155 contract and token using the timed sale strategy",
    async ({ viemClients: { publicClient, walletClient, chain } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
      });
      const {
        parameters: parameters,
        contractAddress,
        newTokenId,
      } = await creatorClient.create1155({
        contract: randomNewContract(),
        token: {
          tokenMetadataURI: demoTokenMetadataURI,
          salesConfig: {
            pricePerToken: 0n,
          },
        },
        account: creatorAddress,
      });

      const { request } = await publicClient.simulateContract(parameters);

      await writeContractWithRetries({ request, walletClient, publicClient });

      expect(
        await minterIsMinterOnToken({
          contractAddress,
          tokenId: newTokenId,
          minter:
            zoraTimedSaleStrategyAddress[
              chain.id as keyof typeof zoraTimedSaleStrategyAddress
            ],
          publicClient,
        }),
      ).toBe(true);
    },
    20 * 1000,
  );

  anvilTest(
    "can create a new contract, then can create a new token on this existing contract",
    async ({ viemClients: { publicClient, walletClient, chain } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAccount = addresses[0]!;

      const contractGetter = new SubgraphContractGetter(chain.id);

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
        contractGetter,
      });

      const { parameters: request, contractAddress: contractAddress } =
        await creatorClient.create1155({
          contract: randomNewContract(),
          token: {
            tokenMetadataURI: demoTokenMetadataURI,
            mintToCreatorCount: 3,
          },
          account: creatorAccount,
        });
      const { request: simulateResponse } =
        await publicClient.simulateContract(request);
      const receipt = await writeContractWithRetries({
        request: simulateResponse,
        walletClient,
        publicClient,
      });
      const firstTokenId = getTokenIdFromCreateReceipt(receipt);
      expect(firstTokenId).to.be.equal(1n);

      // creator should have mint to creator count balance
      expect(
        await publicClient.readContract({
          address: contractAddress,
          abi: zoraCreator1155ImplABI,
          functionName: "balanceOf",
          args: [creatorAccount, firstTokenId!],
        }),
      ).toBe(3n);

      const contractVersion = await publicClient.readContract({
        abi: zoraCreator1155ImplABI,
        address: contractAddress,
        functionName: "contractVersion",
      });

      contractGetter.getContractInfo = vi
        .fn<SubgraphContractGetter["getContractInfo"]>()
        .mockResolvedValueOnce({
          contractVersion,
          mintFee: parseEther("0.000777"),
          name: "test",
          nextTokenId: 2n,
        });

      const newTokenOnExistingContract =
        await creatorClient.create1155OnExistingContract({
          contractAddress: contractAddress,
          token: {
            tokenMetadataURI: demoTokenMetadataURI,
            mintToCreatorCount: 2,
          },
          account: creatorAccount,
        });
      const { request: simulateRequest } = await publicClient.simulateContract(
        newTokenOnExistingContract.parameters,
      );
      const newReceipt = await writeContractWithRetries({
        request: simulateRequest,
        walletClient,
        publicClient,
      });

      const tokenId = getTokenIdFromCreateReceipt(newReceipt);
      expect(tokenId).to.be.equal(2n);
    },
    30 * 1000,
  );
  anvilTest(
    "creates a new token with a create referral address",
    async ({ viemClients: { publicClient, walletClient, chain } }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;
      const createReferral = addresses[1]!;

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
      });
      const {
        parameters: request,
        contractAddress: collectionAddress,
        newTokenId,
      } = await creatorClient.create1155({
        contract: randomNewContract(),
        token: {
          tokenMetadataURI: demoTokenMetadataURI,
          createReferral,
        },
        account: creatorAddress,
      });
      const { request: simulationResponse } =
        await publicClient.simulateContract(request);
      const receipt = await writeContractWithRetries({
        request: simulationResponse,
        walletClient,
        publicClient,
      });

      expect(receipt.to?.toLowerCase()).to.equal(
        "0x777777c338d93e2c7adf08d102d45ca7cc4ed021".toLowerCase(),
      );
      expect(getTokenIdFromCreateReceipt(receipt)).to.be.equal(newTokenId);

      expect(
        await publicClient.readContract({
          abi: zoraCreator1155ImplABI,
          address: collectionAddress,
          functionName: "createReferrals",
          args: [newTokenId],
        }),
      ).to.be.equal(createReferral);
    },
    20 * 1000,
  );

  anvilTest(
    "creates a new 1155 free mint that can be minted",
    async ({
      viemClients: { testClient, publicClient, walletClient, chain },
    }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
      });
      const { parameters: request, prepareMint } =
        await creatorClient.create1155({
          contract: randomNewContract(),
          token: {
            tokenMetadataURI: demoTokenMetadataURI,
          },
          account: creatorAddress,
        });
      const { request: createSimulation } =
        await publicClient.simulateContract(request);

      await writeContractWithRetries({
        request: createSimulation,
        walletClient,
        publicClient,
      });

      const quantityToMint = 5n;

      // now try to mint a free mint
      const minterAddress = addresses[1]!;

      await testClient.setBalance({
        address: minterAddress,
        value: parseEther("10"),
      });

      const { parameters: mintParams } = await prepareMint({
        minterAccount: minterAddress,
        quantityToMint,
      });

      const { request: collectSimulation } =
        await publicClient.simulateContract(mintParams);
      await waitForSuccess(
        await walletClient.writeContract(collectSimulation),
        publicClient,
      );
    },
    20 * 1000,
  );

  anvilTest(
    "creates a new 1155 paid mint that can be minted using the fixed price minter",
    async ({
      viemClients: { testClient, publicClient, walletClient, chain },
    }) => {
      const addresses = await walletClient.getAddresses();
      const creatorAddress = addresses[0]!;

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
      });

      const pricePerToken = parseEther("0.01");

      const {
        parameters: request,
        contractAddress: collectionAddress,
        newTokenId,
        minter,
        contractVersion,
      } = await creatorClient.create1155({
        contract: randomNewContract(),
        token: {
          tokenMetadataURI: demoTokenMetadataURI,
          salesConfig: {
            pricePerToken,
          },
        },
        account: creatorAddress,
      });
      const { request: createSimulation } =
        await publicClient.simulateContract(request);
      await writeContractWithRetries({
        request: createSimulation,
        walletClient,
        publicClient,
      });

      const quantityToMint = 5n;

      // now try to mint a free mint
      const minterAddress = addresses[1]!;

      await testClient.setBalance({
        address: minterAddress,
        value: parseEther("10"),
      });

      const mintParams = makePrepareMint1155TokenParams({
        tokenContract: collectionAddress,
        minterAccount: minterAddress,
        tokenId: newTokenId,
        salesConfigAndTokenInfo: {
          contractVersion,
          salesConfig: {
            mintFeePerQuantity: await publicClient.readContract({
              abi: zoraCreator1155ImplABI,
              functionName: "mintFee",
              address: collectionAddress,
            }),
            saleType: "fixedPrice",
            address: minter,
            pricePerToken,
            // these dont matter
            maxTokensPerAddress: 0n,
            saleEnd: "",
            saleStart: "",
          },
        },
        quantityToMint,
      });

      const { request: collectSimulation } =
        await publicClient.simulateContract(mintParams);
      await waitForSuccess(
        await walletClient.writeContract(collectSimulation),
        publicClient,
      );
    },
    20 * 1000,
  );

  anvilTest(
    "creates an allow list mint contract",
    async ({ viemClients: { publicClient, walletClient, chain } }) => {
      const creator = (await walletClient.getAddresses())[0]!;
      const allowList: AllowList = {
        entries: [
          {
            user: "0xf69fEc6d858c77e969509843852178bd24CAd2B6",
            price: 2n,
            maxCanMint: 10000,
          },
          {
            user: "0xcD08da546414dd463C89705B5E72CE1AeebF1567",
            price: 3n,
            maxCanMint: 10,
          },
        ],
      };

      const root = await createAllowList({
        allowList,
      });

      const creatorClient = createCreatorClient({
        chainId: chain.id,
        publicClient: publicClient,
      });

      const { parameters: parameters } = await creatorClient.create1155({
        contract: {
          name: "test allowlists",
          uri: "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        token: {
          tokenMetadataURI:
            "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          salesConfig: {
            type: "allowlistMint",
            presaleMerkleRoot: `0x${root}`,
          },
        },
        account: creator,
      });

      const { request } = await publicClient.simulateContract(parameters);

      await waitForSuccess(
        await walletClient.writeContract(request),
        publicClient,
      );
    },
  );
});
