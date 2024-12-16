import { makeAnvilTest, simulateAndWriteContractWithRetries } from "./test";
import { describe } from "node:test";
import { base } from "viem/chains";
import { expect } from "vitest";
import { getDeployTokenParameters } from "./deploy";
import { BASE_MAINNET_FORK_BLOCK_NUMBER, forkUrls } from "./test/constants";

describe("deploy wow token", () => {
  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can deploy wow token",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const parameters = await getDeployTokenParameters({
        chainId: base.id,
        userAddress: walletClient.account?.address!,
        cid: "ipfs://test",
        name: "test",
        symbol: "test",
      });
      const receipt = await simulateAndWriteContractWithRetries({
        parameters,
        walletClient,
        publicClient,
      });

      expect(true).toBe(true);

      expect(receipt.status).toBe("success");
    },

    20_000,
  );
});
