import { describe, expect, test } from "vitest";
import { makeAnvilTest } from "../test";
import { base } from "viem/chains";
import { getUniswapQuote } from "./getUniswapQuote";
import { parseEther, zeroAddress } from "viem";
import { getPoolInfo } from "./getPoolInfo";

const forkUrls = {
  baseMainnet: `https://base-mainnet.g.alchemy.com/v2/6GhpfVtPzsbJkGjwfgUjBW`,
};

// Real token with existing pool on Base
const REAL_TOKEN = "0x01aa2894773c091cc21a8880b3633ac173727440";
// Non-existent pool address
const FAKE_POOL = "0x1234567890123456789012345678901234567890";

describe("getUniswapQuote", () => {
  makeAnvilTest({
    forkBlockNumber: 23589888,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })("happy path tests", async ({ viemClients: { publicClient } }) => {
    test("should get valid buy quote", async () => {
      // First get pool info to get the pool address
      const poolInfo = await getPoolInfo(REAL_TOKEN, publicClient);

      const quote = await getUniswapQuote({
        chainId: base.id,
        poolAddress: poolInfo.address,
        amount: parseEther("1"), // 1 ETH
        type: "buy",
        publicClient,
      });

      expect(quote.error).toBeUndefined();
      expect(quote.amountOut).toBeGreaterThan(0n);
      expect(quote.fee).toBeGreaterThan(0);
      expect(quote.balance).toBeDefined();
      expect(quote.balance?.weth).toBeGreaterThan(0n);
      expect(quote.balance?.erc20z).toBeGreaterThan(0n);
    });

    test("should get valid sell quote", async () => {
      const poolInfo = await getPoolInfo(REAL_TOKEN, publicClient);

      const quote = await getUniswapQuote({
        chainId: base.id,
        poolAddress: poolInfo.address,
        amount: parseEther("1000"), // 1000 tokens
        type: "sell",
        publicClient,
      });

      expect(quote.error).toBeUndefined();
      expect(quote.amountOut).toBeGreaterThan(0n);
      expect(quote.fee).toBeGreaterThan(0);
      expect(quote.balance).toBeDefined();
    });

    test("should handle very large buy amounts with insufficient liquidity", async () => {
      const poolInfo = await getPoolInfo(REAL_TOKEN, publicClient);

      const quote = await getUniswapQuote({
        chainId: base.id,
        poolAddress: poolInfo.address,
        amount: parseEther("1000000"), // 1M ETH (unreasonably large)
        type: "buy",
        publicClient,
      });

      expect(quote.error).toBe("Insufficient liquidity");
      expect(quote.amountOut).toBe(0n);
    });
  });

  makeAnvilTest({
    forkBlockNumber: 23589888,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })("unhappy path tests", async ({ viemClients: { publicClient } }) => {
    test("should handle missing pool address", async () => {
      const quote = await getUniswapQuote({
        chainId: base.id,
        poolAddress: undefined,
        amount: parseEther("1"),
        type: "buy",
        publicClient,
      });

      expect(quote.error).toBe("Invalid pool address");
      expect(quote.amountOut).toBe(0n);
    });

    test("should handle invalid pool address", async () => {
      const quote = await getUniswapQuote({
        chainId: base.id,
        poolAddress: FAKE_POOL,
        amount: parseEther("1"),
        type: "buy",
        publicClient,
      });

      expect(quote.error).toBe("Failed fetching pool");
      expect(quote.amountOut).toBe(0n);
    });

    test("should handle zero address pool", async () => {
      const quote = await getUniswapQuote({
        chainId: base.id,
        poolAddress: zeroAddress,
        amount: parseEther("1"),
        type: "buy",
        publicClient,
      });

      expect(quote.error).toBe("Failed fetching pool");
      expect(quote.amountOut).toBe(0n);
    });
  });
});
