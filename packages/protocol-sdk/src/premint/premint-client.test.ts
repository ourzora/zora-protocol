import { zoraSepolia } from "viem/chains";
import { describe, expect, vi } from "vitest";

import { PremintConfigVersion } from "./contract-types";
import { forkUrls, makeAnvilTest } from "src/anvil";
import { PremintAPIClient } from "./premint-api-client";
import { mint } from "../mint/mint-client";
import { getDataFromPremintReceipt } from "./premint-client";
import { zoraCreatorFixedPriceSaleStrategyAddress } from "@zoralabs/protocol-deployments";
import { Address } from "viem";

const anvilTest = makeAnvilTest({
  forkUrl: forkUrls.zoraSepolia,
  forkBlockNumber: 9678162,
  anvilChainId: zoraSepolia.id,
});

function getDefaultFixedPriceMinterAddress(chainId: number): Address {
  return zoraCreatorFixedPriceSaleStrategyAddress[
    chainId as keyof typeof zoraCreatorFixedPriceSaleStrategyAddress
  ]!;
}

describe("ZoraCreator1155Premint", () => {
  anvilTest(
    "can mint premints",
    async ({ viemClients: { walletClient, publicClient, chain } }) => {
      const [deployerAccount] = await walletClient.getAddresses();

      const premintApiClient = new PremintAPIClient(chain.id);

      premintApiClient.get = vi
        .fn<typeof premintApiClient.get>()
        .mockResolvedValue({
          collection: {
            contractAdmin: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
            contractName: "Testing Contract",
            contractURI:
              "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3e",
            additionalAdmins: [],
          },
          collectionAddress: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
          premint: {
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
          },
          signer: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
          signature:
            "0x4d191dd60d428adfe507932a1758bee8ac5bbb77dcd3c05840c237416a3a25035bb8cc7c62177a4e9acb5f40c4032cdb3dbfefdd1575f2c3b4c57945b2076e2e1c",
        });

      premintApiClient.postSignature = vi.fn();

      const { parameters } = await mint({
        mintType: "premint",
        minterAccount: deployerAccount!,
        tokenContract: "0xf8dA7f53c283d898818af7FB9d98103F559bDac2",
        uid: 3,
        quantityToMint: 1,
        mintComment: "",
        publicClient,
        premintGetter: premintApiClient,
      });
      const { request: simulateRequest } =
        await publicClient.simulateContract(parameters);
      const hash = await walletClient.writeContract(simulateRequest);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      const { premintedLog, urls } = getDataFromPremintReceipt(
        receipt,
        publicClient.chain.id,
      );

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
