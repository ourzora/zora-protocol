import { describe, expect } from "vitest";
import { makeAnvilTest } from "../test";
import { base } from "viem/chains";
import { getUniswapQuote } from "./getUniswapQuote";
import { parseEther, zeroAddress } from "viem";
import { getMarketTypeAndPoolAddress } from "../pool/transaction";
import {
  BASE_GRADUATED_TOKEN_ADDRESS,
  BASE_MAINNET_FORK_BLOCK_NUMBER,
  forkUrls,
} from "../test/constants";

// Non-existent pool address
const FAKE_POOL = "0x1234567890123456789012345678901234567890";

describe("getUniswapQuote", () => {
  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can fetch a buy uniswap quote",
    async ({ viemClients: { publicClient } }) => {
      // First get pool info to get the pool address
      const { poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });

      const quote = await getUniswapQuote({
        poolAddress,
        amount: parseEther("1"),
        type: "buy",
        publicClient,
      });

      expect(quote.error).toBeUndefined();
      expect(quote.amountOut).toBeGreaterThan(0n);
      expect(quote.fee).toBeGreaterThan(0);
      expect(quote.balance).toBeDefined();
      expect(quote.balance?.weth).toBeGreaterThan(0n);
      expect(quote.balance?.erc20z).toBeGreaterThan(0n);
    },
    10_000,
  );

  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can fetch a sell uniswap quote",
    async ({ viemClients: { publicClient } }) => {
      const { poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });

      const quote = await getUniswapQuote({
        poolAddress,
        amount: parseEther("1000"),
        type: "sell",
        publicClient,
      });

      expect(quote.error).toBeUndefined();
      expect(quote.amountOut).toBeGreaterThan(0n);
      expect(quote.fee).toBeGreaterThan(0);
      expect(quote.balance).toBeDefined();
    },
    10_000,
  );

  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "should handle invalid pool address",
    async ({ viemClients: { publicClient } }) => {
      const quote = await getUniswapQuote({
        poolAddress: FAKE_POOL,
        amount: parseEther("1"),
        type: "buy",
        publicClient,
      });

      expect(quote.error?.message).toBe("Failed fetching pool");
      expect(quote.amountOut).toBe(0n);
    },
  );

  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "should handle zero address pool",
    async ({ viemClients: { publicClient } }) => {
      const quote = await getUniswapQuote({
        poolAddress: zeroAddress,
        amount: parseEther("1"),
        type: "buy",
        publicClient,
      });

      expect(quote.error?.message).toBe("Failed fetching pool");
      expect(quote.amountOut).toBe(0n);
    },
  );
});
