import { foundry } from "viem/chains";
import { describe, expect, vi } from "vitest";

import { createPremintClient } from "./premint-client";
import { anvilTest } from "src/anvil";
import { PremintConfigVersion } from "./contract-types";
import { getDefaultFixedPriceMinterAddress } from "./preminter";

describe("ZoraCreator1155Premint - v1 signatures", () => {
  anvilTest(
    "can sign by default v1 on the forked premint contract",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      const [deployerAccount] = await walletClient.getAddresses();
      const premintClient = createPremintClient({
        chain,
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
            fixedPriceMinter: getDefaultFixedPriceMinterAddress(chain.id),
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
          "0x70fc1d6e862c42f2b0e4a062f4eb973cc8692df58a24b71b4fe91ae7baa5a26d2c99b1b8ab61f64ff431bf30b0897877b11b7405542c90b89b041808f1561a6c1c",
      };

      expect(premintClient.apiClient.postSignature).toHaveBeenCalledWith(
        expectedPostSignatureArgs,
      );
    },
    20 * 1000,
  );

  anvilTest(
    "can execute premint on network",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
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
              fixedPriceMinter: getDefaultFixedPriceMinterAddress(chain.id),
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
            "0x70fc1d6e862c42f2b0e4a062f4eb973cc8692df58a24b71b4fe91ae7baa5a26d2c99b1b8ab61f64ff431bf30b0897877b11b7405542c90b89b041808f1561a6c1c",
        });

      premintClient.apiClient.postSignature = vi.fn();

      const simulateContractParameters = await premintClient.makeMintParameters(
        {
          minterAccount: deployerAccount!,
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
        createdNewContract: expect.any(Boolean),
        minter: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        quantityMinted: 1n,
        tokenId: 1n,
        uid: 3,
      });
    },
    20 * 1000,
  );
});

describe("ZoraCreator1155Premint - v2 signatures", () => {
  anvilTest(
    "can sign on the forked premint contract",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      const [creatorAccount, createReferralAccount] =
        await walletClient.getAddresses();
      const premintClient = createPremintClient({
        chain,
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
          "0x8be7932b0b31bdb7fc9269b756e0d0c9514519f083d86576e23b73c033d8ed8440ea363bc8bba0ec5c30eb6bbdf796163a324201bc7520965037102518fb5e991c",
      };

      expect(premintClient.apiClient.postSignature).toHaveBeenCalledWith(
        expectedPostSignatureArgs,
      );
    },
    20 * 1000,
  );
});
