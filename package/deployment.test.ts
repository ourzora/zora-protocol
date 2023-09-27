import { foundry, zoraTestnet } from "viem/chains";
import { Address, createTestClient, createWalletClient, http } from "viem";
import { describe, it, beforeEach, expect, TestContext } from "vitest";
import { testConfig } from "./deploymentConfig";
import { getDeployFactoryProxyDeterminsticTx } from "./deployment";

export const testClient = createTestClient({
  chain: foundry,
  mode: "anvil",
  transport: http(),
});

describe("DeterminsticDeployment", () => {
  beforeEach<TestContext>(async (ctx) => {
    // deploy signature minter contract
  }, 20 * 1000);

  // skip for now - we need to make this work on zora testnet chain too
  it(
    "can determnistically deploy a factory at the expected address",
    async ({}) => {
      const testClient = createTestClient({
        chain: foundry,
        mode: "anvil",
        transport: http(),
      });

      const walletClient = createWalletClient({
        chain: foundry,
        transport: http(),
      });

      const [
        deployerAccount,
        creatorAccount,
        collectorAccount,
        mintFeeRecipientAccount,
      ] = (await walletClient.getAddresses()) as [
        Address,
        Address,
        Address,
        Address
      ];

      // pre-sign transactions
      await testClient.impersonateAccount({
        address: testConfig.deployerAddress,
      });
    },
    20 * 1000
  );
});
