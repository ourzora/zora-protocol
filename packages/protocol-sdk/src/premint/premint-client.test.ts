import { foundry } from "viem/chains";
import { describe, expect, vi } from "vitest";
import { PremintClient } from "./premint-client";
import { BackendChainNamesLookup } from "../apis/client-base";
import { anvilTest } from "src/anvil";

describe("ZoraCreator1155Premint", () => {
  anvilTest(
    "can sign on the forked premint contract",
    async ({ viemClients: { walletClient, publicClient } }) => {
      const [deployerAccount] = await walletClient.getAddresses();
      const premintClient = new PremintClient(foundry);

      premintClient.apiClient.getNextUID = vi
        .fn()
        .mockResolvedValue({ next_uid: 3 });
      premintClient.apiClient.postSignature = vi
        .fn()
        .mockResolvedValue({ ok: true });

      await premintClient.createPremint({
        walletClient,
        publicClient,
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
        chain_name: BackendChainNamesLookup.ZORA_GOERLI,
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
      const premintClient = new PremintClient(foundry);

      const premintData = {
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
        chain_name: "ZORA-TESTNET",
        signature:
          "0x588d19641de9ba1dade4d2bb5387c8dc96f4a990fef69787534b60caead759e6334975a6be10a796da948cd7d1d4f5580b3f84d49d9fa4e0b41c97759507975a1c",
      } as const;

      const signatureValid = await premintClient.isValidSignature({
        // @ts-ignore: Fix enum type
        data: premintData,
        publicClient,
      });
      expect(signatureValid.isValid).toBe(true);
    },
  );

  anvilTest(
    "can execute premint on network",
    async ({ viemClients: { walletClient, publicClient } }) => {
      const [deployerAccount] = await walletClient.getAddresses();
      const premintClient = new PremintClient(foundry);

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

      const premint = await premintClient.executePremintWithWallet({
        data: await premintClient.getPremintData({
          address: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
          uid: 3,
        }),
        account: deployerAccount,
        walletClient,
        publicClient,
        mintArguments: {
          quantityToMint: 1,
          mintComment: "",
        },
      });

      expect(premint.premintedLog).toEqual({
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
