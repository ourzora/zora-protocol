import { foundry, zoraSepolia } from "viem/chains";
import { describe, expect, vi } from "vitest";

import { createPremintClient } from "./premint-client";
import { PremintConfigVersion } from "./contract-types";
import { getDefaultFixedPriceMinterAddress } from "./preminter";
import { forkUrls, makeAnvilTest } from "src/anvil";

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraSepolia,
  forkBlockNumber: 8869648,
  anvilChainId: zoraSepolia.id,
});

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

      const { signAndSubmit } = await premintClient.createPremint({
        payoutRecipient: deployerAccount!,
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

      await signAndSubmit({
        walletClient,
        checkSignature: true,
        account: deployerAccount!,
      });

      const expectedPostSignatureArgs: Parameters<
        typeof premintClient.apiClient.postSignature
      >[0] = {
        collection: {
          contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          contractName: "Testing Contract",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
          additionalAdmins: [],
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
          "0x4d191dd60d428adfe507932a1758bee8ac5bbb77dcd3c05840c237416a3a25035bb8cc7c62177a4e9acb5f40c4032cdb3dbfefdd1575f2c3b4c57945b2076e2e1c",
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
            additionalAdmins: [],
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
            "0x4d191dd60d428adfe507932a1758bee8ac5bbb77dcd3c05840c237416a3a25035bb8cc7c62177a4e9acb5f40c4032cdb3dbfefdd1575f2c3b4c57945b2076e2e1c",
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

      const { signAndSubmit } = await premintClient.createPremint({
        payoutRecipient: creatorAccount!,
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

      await signAndSubmit({
        account: creatorAccount!,
        walletClient,
        checkSignature: true,
      });

      const expectedPostSignatureArgs: Parameters<
        typeof premintClient.apiClient.postSignature
      >[0] = {
        collection: {
          contractAdmin: creatorAccount!,
          contractName: "Testing Contract Premint V2",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
          additionalAdmins: [],
        },
        premintConfig: {
          deleted: false,
          tokenConfig: {
            fixedPriceMinter: "0x6d28164C3CE04A190D5F9f0f8881fc807EAD975A",
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
          "0x5cc8c0ab240920282cf936d8b5eb1dd151a91ad78cc4e89f8ddeae6ea432ce7904a38e145b734bdd438f18d457451cb1ae28beb2c44bda71d58638dfcc071e1b1c",
      };

      expect(premintClient.apiClient.postSignature).toHaveBeenCalledWith(
        expectedPostSignatureArgs,
      );
    },
    20 * 1000,
  );
});
