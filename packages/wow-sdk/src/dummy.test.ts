import { base } from "viem/chains";
import { describe, expect } from "vitest";
import { forkUrls } from "./sell.test";
import { makeAnvilTest } from "./test";

describe("dummy test", () => {
  makeAnvilTest({
    forkBlockNumber: 23589888,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can buy and then sell token",
    async ({
      viemClients: { publicClient: _publicClient, walletClient: _walletClient },
    }) => {
      expect(true).toBe(true);
    },
  );
});
