import { makeAnvilTest } from "./test";
import { describe } from "node:test";
import { base } from "viem/chains";
import { expect } from "vitest";
import { deployWowToken } from "./deploy";
import { TransactionReceipt } from "viem";

export const forkUrls = {
  baseMainnet: `https://base-mainnet.g.alchemy.com/v2/6GhpfVtPzsbJkGjwfgUjBW`,
};

describe("deploy wow token", () => {
  makeAnvilTest({
    forkBlockNumber: 23589888,
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
