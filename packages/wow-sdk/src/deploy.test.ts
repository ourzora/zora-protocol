import { makeAnvilTest } from "./test";
import { describe } from "node:test";
import { base } from "viem/chains";
import { expect } from "vitest";
import { deployWowToken } from "./deploy";
import { TransactionReceipt } from "viem";
import { BASE_MAINNET_FORK_BLOCK_NUMBER, forkUrls } from "./test/constants";

describe("deploy wow token", () => {
  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can deploy wow token",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const hash = await deployWowToken(
        {
          chainId: base.id,
          userAddress: walletClient.account?.address!,
          cid: "ipfs://test",
          name: "test",
          symbol: "test",
        },
        publicClient,
        walletClient,
      );
      expect(true).toBe(true);

      let receipt: TransactionReceipt | undefined;
      const tryGetReceipt = async () => {
        try {
          receipt = await publicClient.getTransactionReceipt({ hash });
        } catch (e) {}
      };

      await tryGetReceipt();
      while (!receipt) {
        await new Promise((resolve) => setTimeout(resolve, 1000));
        await tryGetReceipt();
      }

      expect(receipt.status).toBe("success");
    },

    20_000,
  );
});
