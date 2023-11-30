import { foundry } from "viem/chains";
import { describe, expect, vi } from "vitest";
import { createPremintClient } from "./premint-client";
import { anvilTest, forkUrls, makeAnvilTest } from "src/anvil";
import { PremintSignatureResponse } from "./premint-api-client";

describe("ZoraCreator1155Premint", () => {
  makeAnvilTest({
    forkUrl: forkUrls.zoraGoerli,
    forkBlockNumber: 1763437,
  })(
    "can sign on the forked premint contract",
    async ({ viemClients: { walletClient, publicClient } }) => {
      const [deployerAccount] = await walletClient.getAddresses();
      const premintClient = createPremintClient({
        chain: foundry,
        publicClient,
      });

      premintClient.apiClient.getNextUID = vi
        .fn()
        .mockResolvedValue({ next_uid: 3 });
      premintClient.apiClient.postSignature = vi
        .fn()
        .mockResolvedValue({ ok: true });

      await premintClient.createPremint({
        walletClient,
        account: deployerAccount!,
        checkSignature: true,
        collection: {
          contractAdmin: deployerAccount!,
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        token: {
          tokenURI:
            "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
        },
      });

      expect(premintClient.apiClient.postSignature).toHaveBeenCalledWith({
        collection: {
          contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        premint: {
          deleted: false,
          tokenConfig: {
            fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
            maxSupply: "18446744073709551615",
            maxTokensPerAddress: "0",
            mintDuration: "604800",
            mintStart: "0",
            pricePerToken: "0",
            royaltyBPS: 1000,
            royaltyMintSchedule: 0,
            royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            tokenURI:
              "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          },
          uid: 3,
          version: 1,
        },
        signature:
          "0x588d19641de9ba1dade4d2bb5387c8dc96f4a990fef69787534b60caead759e6334975a6be10a796da948cd7d1d4f5580b3f84d49d9fa4e0b41c97759507975a1c",
      });
    },
    20 * 1000,
  );

  anvilTest(
    "can validate premint on network",
    async ({ viemClients: { publicClient } }) => {
      const premintClient = createPremintClient({
        chain: foundry,
        publicClient,
      });

      const premintData: PremintSignatureResponse = {
        collection: {
          contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        premint: {
          uid: 3,
          version: 1,
          deleted: false,
          tokenConfig: {
            maxSupply: "18446744073709551615",
            maxTokensPerAddress: "0",
            pricePerToken: "0",
            mintDuration: "604800",
            mintStart: "0",
            royaltyMintSchedule: 0,
            royaltyBPS: 1000,
            fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
            royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            tokenURI:
              "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          },
        },
        chain_name: "ZORA-GOERLI",
        signature:
          "0x588d19641de9ba1dade4d2bb5387c8dc96f4a990fef69787534b60caead759e6334975a6be10a796da948cd7d1d4f5580b3f84d49d9fa4e0b41c97759507975a1c",
      } as const;

      const signatureValid = await premintClient.isValidSignature(premintData);
      expect(signatureValid.isValid).toBe(true);
    },
  );

  anvilTest(
    "can execute premint on network",
    async ({ viemClients: { walletClient, publicClient } }) => {
      const [deployerAccount] = await walletClient.getAddresses();
      const premintClient = createPremintClient({ chain: foundry });

      premintClient.apiClient.getSignature = vi.fn().mockResolvedValue({
        chain_name: "ZORA-TESTNET",
        collection: {
          contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        premint: {
          deleted: false,
          tokenConfig: {
            fixedPriceMinter: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a",
            maxSupply: "18446744073709551615",
            maxTokensPerAddress: "0",
            mintDuration: "604800",
            mintStart: "0",
            pricePerToken: "0",
            royaltyBPS: 1000,
            royaltyMintSchedule: 0,
            royaltyRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            tokenURI:
              "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          },
          uid: 3,
          version: 1,
        },
        signature:
          "0x588d19641de9ba1dade4d2bb5387c8dc96f4a990fef69787534b60caead759e6334975a6be10a796da948cd7d1d4f5580b3f84d49d9fa4e0b41c97759507975a1c",
      });
      premintClient.apiClient.postSignature = vi.fn();

      const simulateContractParameters = await premintClient.makeMintParameters(
        {
          account: deployerAccount!,
          data: await premintClient.getPremintData({
            address: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
            uid: 3,
          }),
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
