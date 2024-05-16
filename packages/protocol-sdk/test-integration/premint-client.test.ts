import { zoraSepolia, zoraTestnet } from "viem/chains";
import { describe } from "vitest";

import { createPremintClient } from "src/premint/premint-client";
import { forkUrls, makeAnvilTest } from "src/anvil";
import { PremintConfigVersion } from "src/premint/contract-types";

const zoraGoerliTest = makeAnvilTest({
  forkBlockNumber: 2107926,
  forkUrl: forkUrls.zoraGoerli,
  anvilChainId: zoraTestnet.id,
});

const zoraSepoliaTest = makeAnvilTest({
  forkBlockNumber: 3118200,
  forkUrl: forkUrls.zoraSepolia,
  anvilChainId: zoraSepolia.id,
});

const tests = [
  {
    anvilTest: zoraGoerliTest,
    chain: zoraTestnet,
  },
  {
    anvilTest: zoraSepoliaTest,
    chain: zoraSepolia,
  },
];

tests.forEach(({ anvilTest, chain }) => {
  describe(chain.name, () => {
    describe("ZoraCreator1155Premint", () => {
      describe("v2 signatures", () => {
        anvilTest(
          "can sign and execute on the forked premint contract",
          async ({
            viemClients: { walletClient, publicClient, testClient },
          }) => {
            const [creatorAccount, createReferralAccount, minterAccount] =
              await walletClient.getAddresses();
            const premintClient = createPremintClient({
              chain,
              publicClient,
            });

            const { uid, verifyingContract } =
              await premintClient.createPremint({
                walletClient,
                creatorAccount: creatorAccount!,
                checkSignature: true,
                collection: {
                  contractAdmin: creatorAccount!,
                  contractName: "Testing Contract Premint V2",
                  contractURI:
                    "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3f",
                  additionalAdmins: [],
                },
                premintConfigVersion: PremintConfigVersion.V2,
                tokenCreationConfig: {
                  tokenURI:
                    "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2f",
                  createReferral: createReferralAccount!,
                },
              });

            const mintParameters = await premintClient.makeMintParameters({
              minterAccount: minterAccount!,
              tokenContract: verifyingContract,
              uid,
            });

            const mintCosts = await premintClient.getMintCosts({
              tokenContract: verifyingContract,
              quantityToMint: 1n,
              pricePerToken: 0n,
            });

            await testClient.setBalance({
              address: minterAccount!,
              value: mintCosts.totalCost,
            });

            // if simulation succeeds, mint will succeed
            await publicClient.simulateContract(mintParameters);
          },
          20 * 1000,
        );
      });

      describe("v1 signatures", () => {
        anvilTest(
          "can sign and execute on the forked premint contract",
          async ({
            viemClients: { walletClient, publicClient, testClient },
          }) => {
            const [creatorAccount, minterAccount] =
              await walletClient.getAddresses();
            const premintClient = createPremintClient({
              chain,
              publicClient,
            });

            const { uid, verifyingContract } =
              await premintClient.createPremint({
                walletClient,
                creatorAccount: creatorAccount!,
                checkSignature: true,
                collection: {
                  contractAdmin: creatorAccount!,
                  contractName: `Testing Contract Premint V1 ${publicClient.chain?.name}`,
                  contractURI:
                    "ipfs://bafkreiainxen4b4wz4ubylvbhons6rembxdet4a262nf2lziclqvv7au3fg",
                  additionalAdmins: [],
                },
                premintConfigVersion: PremintConfigVersion.V1,
                tokenCreationConfig: {
                  tokenURI:
                    "ipfs://bafkreice23maski3x52tsfqgxstx3kbiifnt5jotg3a5ynvve53c4soi2u",
                },
              });

            const mintParameters = await premintClient.makeMintParameters({
              minterAccount: minterAccount!,
              tokenContract: verifyingContract,
              uid,
            });

            const mintCosts = await premintClient.getMintCosts({
              tokenContract: verifyingContract,
              quantityToMint: 1n,
              pricePerToken: 0n,
            });

            await testClient.setBalance({
              address: minterAccount!,
              value: mintCosts.totalCost,
            });

            // if simulation succeeds, mint will succeed
            await publicClient.simulateContract(mintParameters);
          },
          20 * 1000,
        );
      });
    });
  });
});
