import { foundry } from "viem/chains";
import { describe, expect, vi } from "vitest";

import { Address, Hex } from "viem";
import { createPremintClient } from "./premint-client";
import { forkUrls, makeAnvilTest } from "src/anvil";
import {
  ContractCreationConfig,
  PremintConfigV1,
  PremintConfigVersion,
} from "./contract-types";

const zoraMainnetForkAnvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraMainnet,
  forkBlockNumber: 7550118,
});

describe("ZoraCreator1155Premint - v1 signatures", () => {
  zoraMainnetForkAnvilTest(
    "can sign by default v1 on the forked premint contract",
    async ({ viemClients: { walletClient, publicClient } }) => {
      const [deployerAccount] = await walletClient.getAddresses();
      const premintClient = createPremintClient({
        chain: foundry,
        publicClient,
      });

      premintClient.apiClient.getNextUID = vi
        .fn<any, ReturnType<typeof premintClient.apiClient.getNextUID>>()
        .mockResolvedValue(3);
      premintClient.apiClient.postSignature = vi
        .fn<Parameters<typeof premintClient.apiClient.postSignature>>()
        .mockResolvedValue({ ok: true });

      await premintClient.createPremint({
        walletClient,
        creatorAccount: deployerAccount!,
        checkSignature: true,
        collection: {
          contractAdmin: deployerAccount!,
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        tokenCreationConfig: {
          tokenURI:
            "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
        },
      });

      const expectedPostSignatureArgs: Parameters<
        typeof premintClient.apiClient.postSignature
      >[0] = {
        collection: {
          contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        premintConfig: {
          deleted: false,
          tokenConfig: {
            fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
            maxSupply: 18446744073709551615n,
            maxTokensPerAddress: 0n,
            mintDuration: 604800n,
            mintStart: 0n,
            pricePerToken: 0n,
            royaltyBPS: 1000,
            royaltyMintSchedule: 0,
            royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            tokenURI:
              "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          },
          uid: 3,
          version: 0,
        },
        premintConfigVersion: PremintConfigVersion.V1,
        signature:
          "0x8c6a9160a0917d98c201b37c9220c17ebaed23a5f905202341c1d0d4e8673c3913880907d6de48c9858fbeb40a9a38d5edda979e4dcb133643ca8ecb4afe0b691b",
      };

      expect(premintClient.apiClient.postSignature).toHaveBeenCalledWith(
        expectedPostSignatureArgs,
      );
    },
    20 * 1000,
  );

  zoraMainnetForkAnvilTest(
    "can validate premint on network",
    async ({ viemClients: { publicClient } }) => {
      const premintClient = createPremintClient({
        chain: foundry,
        publicClient,
      });

      const collection: ContractCreationConfig = {
        contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as Address,
        contractName: "Testing Contract",
        contractURI:
          "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
      };
      const premint: PremintConfigV1 = {
        uid: 3,
        version: 1,
        deleted: false,
        tokenConfig: {
          maxSupply: 18446744073709551615n,
          maxTokensPerAddress: 0n,
          pricePerToken: 0n,
          mintDuration: 604800n,
          mintStart: 0n,
          royaltyMintSchedule: 0,
          royaltyBPS: 1000,
          fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
          royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          tokenURI:
            "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
        },
      };

      const signature =
        "0x588d19641de9ba1dade4d2bb5387c8dc96f4a990fef69787534b60caead759e6334975a6be10a796da948cd7d1d4f5580b3f84d49d9fa4e0b41c97759507975a1c" as Hex;

      const signatureValid = await premintClient.isValidSignature({
        collection: collection,
        premintConfig: premint,
        signature,
        // default to premint config v1 version (we dont need to specify it here)
      });
      expect(signatureValid.isValid).toBe(true);
    },
  );

  zoraMainnetForkAnvilTest(
    "can execute premint on network",
    async ({ viemClients: { walletClient, publicClient } }) => {
      const [deployerAccount] = await walletClient.getAddresses();
      const premintClient = createPremintClient({
        chain: foundry,
        publicClient,
      });

      premintClient.apiClient.getSignature = vi
        .fn<any, ReturnType<typeof premintClient.apiClient.getSignature>>()
        .mockResolvedValue({
          collection: {
            contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            contractName: "Testing Contract",
            contractURI:
              "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
          },
          premintConfig: {
            deleted: false,
            tokenConfig: {
              fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
              maxSupply: 18446744073709551615n,
              maxTokensPerAddress: 0n,
              mintDuration: 604800n,
              mintStart: 0n,
              pricePerToken: 0n,
              royaltyBPS: 1000,
              royaltyMintSchedule: 0,
              royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
              tokenURI:
                "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
            },
            uid: 3,
            version: 1,
          },
          premintConfigVersion: PremintConfigVersion.V1,
          signature:
            "0x588d19641de9ba1dade4d2bb5387c8dc96f4a990fef69787534b60caead759e6334975a6be10a796da948cd7d1d4f5580b3f84d49d9fa4e0b41c97759507975a1c",
        });

      premintClient.apiClient.postSignature = vi.fn();

      const simulateContractParameters = await premintClient.makeMintParameters(
        {
          account: deployerAccount!,
          tokenContract: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
          uid: 3,
          mintArguments: {
            quantityToMint: 1,
            mintComment: "",
          },
        },
      );
      const { request: simulateRequest } = await publicClient.simulateContract(
        simulateContractParameters,
      );
      const hash = await walletClient.writeContract(simulateRequest);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const { premintedLog, urls } =
        premintClient.getDataFromPremintReceipt(receipt);

      expect(urls).toEqual({
        explorer:
          "https://undefined/token/0xf8dA7f53c283d898818af7FB9d98103F559bDac2/instance/1",
        zoraCollect:
          "https://testnet.zora.co/collect/zgor:0xf8dA7f53c283d898818af7FB9d98103F559bDac2/1",
        zoraManage:
          "https://testnet.zora.co/collect/zgor:0xf8dA7f53c283d898818af7FB9d98103F559bDac2/1",
      });

      expect(premintedLog).toEqual({
        contractAddress: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
        contractConfig: {
          contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        createdNewContract: expect.any(Boolean),
        minter: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        quantityMinted: 1n,
        tokenConfig: {
          fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
          maxSupply: 18446744073709551615n,
          maxTokensPerAddress: 0n,
          mintDuration: 604800n,
          mintStart: 0n,
          pricePerToken: 0n,
          royaltyBPS: 1000,
          royaltyMintSchedule: 0,
          royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          tokenURI:
            "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
        },
        tokenId: 1n,
        uid: 3,
      });
    },
    20 * 1000,
  );
});

describe("ZoraCreator1155Premint - v2 signatures", () => {
  makeAnvilTest({
    forkUrl: forkUrls.zoraSepolia,
    forkBlockNumber: 1865004,
  })(
    "can sign on the forked premint contract",
    async ({ viemClients: { walletClient, publicClient } }) => {
      const [creatorAccount, createReferralAccount] =
        await walletClient.getAddresses();
      const premintClient = createPremintClient({
        chain: foundry,
        publicClient,
      });

      premintClient.apiClient.getNextUID = vi
        .fn<any, ReturnType<typeof premintClient.apiClient.getNextUID>>()
        .mockResolvedValue(3);
      premintClient.apiClient.postSignature = vi
        .fn<Parameters<typeof premintClient.apiClient.postSignature>>()
        .mockResolvedValue({ ok: true });

      await premintClient.createPremint({
        walletClient,
        creatorAccount: creatorAccount!,
        checkSignature: true,
        collection: {
          contractAdmin: creatorAccount!,
          contractName: "Testing Contract Premint V2",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        premintConfigVersion: PremintConfigVersion.V2,
        tokenCreationConfig: {
          tokenURI:
            "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          createReferral: createReferralAccount,
        },
      });

      const expectedPostSignatureArgs: Parameters<
        typeof premintClient.apiClient.postSignature
      >[0] = {
        collection: {
          contractAdmin: creatorAccount!,
          contractName: "Testing Contract Premint V2",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        premintConfig: {
          deleted: false,
          tokenConfig: {
            fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
            maxSupply: 18446744073709551615n,
            maxTokensPerAddress: 0n,
            mintDuration: 604800n,
            mintStart: 0n,
            pricePerToken: 0n,
            royaltyBPS: 1000,
            payoutRecipient: creatorAccount!,
            createReferral: createReferralAccount!,
            tokenURI:
              "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          },
          uid: 3,
          version: 0,
        },
        premintConfigVersion: PremintConfigVersion.V2,
        signature:
          "0xd0a9d8164911237430fe2c76ccfd4f53925a9e14e29da19b98ed5ed59e262b0d6ef24efe8b828b79e7b2fe5a60b81c3ce0f40b58d88619dcca131c87703d9f1f1c",
      };

      expect(premintClient.apiClient.postSignature).toHaveBeenCalledWith(
        expectedPostSignatureArgs,
      );
    },
    20 * 1000,
  );
});
