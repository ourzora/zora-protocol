import { zoraSepolia } from "viem/chains";
import { describe, expect, vi } from "vitest";

import { PremintConfigVersion } from "./contract-types";
import {
  getDefaultFixedPriceMinterAddress,
  getPremintCollectionAddress,
} from "./preminter";
import { forkUrls, makeAnvilTest } from "src/anvil";
import {
  ContractCreationConfig,
  PremintConfigV2,
} from "@zoralabs/protocol-deployments";
import { PremintAPIClient } from "./premint-api-client";
import { createCollectorClient, createCreatorClient } from "src/sdk";

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraSepolia,
  forkBlockNumber: 9678162,
  anvilChainId: zoraSepolia.id,
});

describe("ZoraCreator1155Premint", () => {
  anvilTest(
    "can mint premints",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      const [deployerAccount] = await walletClient.getAddresses();

      const premintApiClient = new PremintAPIClient(chain.id);

      premintApiClient.getSignature = vi
        .fn<any, ReturnType<typeof premintApiClient.getSignature>>()
        .mockResolvedValue({
          collection: {
            contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            contractName: "Testing Contract",
            contractURI:
              "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
            additionalAdmins: [],
          },
          collectionAddress: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
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

      premintApiClient.postSignature = vi.fn();

      const collectorClient = createCollectorClient({
        chain,
        publicClient,
        premintGetter: premintApiClient,
      });

      const simulateContractParameters = await collectorClient.mint({
        mintType: "premint",
        minterAccount: deployerAccount!,
        tokenContract: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
        uid: 3,
        quantityToMint: 1,
        mintComment: "",
      });
      const { request: simulateRequest } = await publicClient.simulateContract(
        simulateContractParameters,
      );
      const hash = await walletClient.writeContract(simulateRequest);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      const { premintedLog, urls } =
        collectorClient.getCollectDataFromPremintReceipt(receipt);

      expect(urls).toEqual({
        explorer:
          "https://undefined/token/0xf8dA7f53c283d898818af7FB9d98103F559bDac2/instance/1",
        zoraCollect:
          "https://testnet.zora.co/collect/zsep:0xf8dA7f53c283d898818af7FB9d98103F559bDac2/1",
        zoraManage:
          "https://testnet.zora.co/collect/zsep:0xf8dA7f53c283d898818af7FB9d98103F559bDac2/1",
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
    "can sign and submit new premints on new contracts",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      const [creatorAccount, createReferralAccount] =
        await walletClient.getAddresses();
      const premintApiClient = new PremintAPIClient(chain.id);

      premintApiClient.getNextUID = vi
        .fn<any, ReturnType<typeof premintApiClient.getNextUID>>()
        .mockResolvedValue(3);
      premintApiClient.postSignature = vi
        .fn<Parameters<typeof premintApiClient.postSignature>>()
        .mockResolvedValue({ ok: true });

      const creatorClient = createCreatorClient({
        chain,
        premintApi: premintApiClient,
        publicClient,
      });

      const { signAndSubmit } = await creatorClient.createPremint({
        collection: {
          contractAdmin: creatorAccount!,
          contractName: "Testing Contract Premint V2",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        tokenCreationConfig: {
          tokenURI:
            "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
          payoutRecipient: creatorAccount!,
          createReferral: createReferralAccount,
        },
      });

      await signAndSubmit({
        account: creatorAccount!,
        walletClient,
        checkSignature: true,
      });

      const expectedPostSignatureArgs: Parameters<
        typeof premintApiClient.postSignature
      >[0] = {
        collection: {
          contractAdmin: creatorAccount!,
          contractName: "Testing Contract Premint V2",
          contractURI:
            "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        },
        collectionAddress: undefined,
        premintConfig: {
          deleted: false,
          tokenConfig: {
            fixedPriceMinter: "0x6d28164C3CE04A190D5F9f0f8881fc807EAD975A",
            maxSupply: 18446744073709551615n,
            maxTokensPerAddress: 0n,
            mintDuration: 0n,
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
          "0xfe5725c05754ad17a73cc9706bf940e30bd7b4a674bb1b283a66a1cc87022c8c13fcf8989f9feb675f8932a6a8ddb8d16af2abef28fa2fff3282487ef5385b3d1b",
      };

      expect(premintApiClient.postSignature).toHaveBeenCalledWith(
        expectedPostSignatureArgs,
      );
    },
    20 * 1000,
  );

  anvilTest(
    "can mint premints with additional admins",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      const [deployerAccount, creatorAccount, additionalAdmin] =
        await walletClient.getAddresses();

      const premintApiClient = new PremintAPIClient(chain.id);

      const collectorClient = createCollectorClient({
        chain,
        publicClient,
        premintGetter: premintApiClient,
      });

      const creatorClient = createCreatorClient({
        chain,
        publicClient,
        premintApi: premintApiClient,
      });

      const collection: ContractCreationConfig = {
        contractAdmin: creatorAccount!,
        contractName: "Testing Contract",
        contractURI:
          "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
        additionalAdmins: [additionalAdmin!],
      };

      const collectionAddress = await getPremintCollectionAddress({
        collection,
        publicClient,
      });

      const { premintConfig, typedDataDefinition } =
        await creatorClient.createPremint({
          collection,
          tokenCreationConfig: {
            tokenURI:
              "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
            payoutRecipient: creatorAccount!,
          },
        });

      const signature = await walletClient.signTypedData({
        ...typedDataDefinition,
        account: additionalAdmin!,
      });

      premintApiClient.getSignature = vi
        .fn<any, ReturnType<typeof premintApiClient.getSignature>>()
        .mockResolvedValue({
          collection,
          collectionAddress,
          premintConfig: premintConfig as PremintConfigV2,
          premintConfigVersion: PremintConfigVersion.V2,
          signature,
        });

      const simulateContractParameters = await collectorClient.mint({
        mintType: "premint",
        uid: premintConfig.uid,
        minterAccount: deployerAccount!,
        tokenContract: collectionAddress,
        quantityToMint: 1,
        mintComment: "",
      });
      const { request: simulateRequest } = await publicClient.simulateContract(
        simulateContractParameters,
      );
      const hash = await walletClient.writeContract(simulateRequest);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      const { premintedLog, urls } =
        collectorClient.getCollectDataFromPremintReceipt(receipt);

      expect(urls).toEqual({
        explorer: `https://undefined/token/${collectionAddress}/instance/1`,
        zoraCollect: `https://testnet.zora.co/collect/zsep:${collectionAddress}/1`,
        zoraManage: `https://testnet.zora.co/collect/zsep:${collectionAddress}/1`,
      });

      expect(premintedLog).toEqual({
        contractAddress: collectionAddress,
        createdNewContract: expect.any(Boolean),
        minter: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        quantityMinted: 1n,
        tokenId: 1n,
        uid: premintConfig.uid,
      });
    },
    20 * 1000,
  );
});
