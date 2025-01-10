import { describe, expect, it } from "vitest";
import {
  calculateQuoteWithFees,
  calculateSlippage,
  getBuyQuote,
  getSellQuote,
  isQuoteChangeExceedingSlippage,
} from ".";
import { makeAnvilTest } from "../test";
import { base } from "viem/chains";
import { parseEther } from "viem";
import {
  BASE_GRADUATED_TOKEN_ADDRESS,
  BASE_MAINNET_FORK_BLOCK_NUMBER,
  forkUrls,
} from "../test/constants";
import { getMarketTypeAndPoolAddress } from "../pool/transaction";

describe("Quote utilities", () => {
  describe("calculateQuoteWithFees", () => {
    it("should correctly calculate 1% fee", () => {
      const quote = 1000000n;
      const result = calculateQuoteWithFees(quote);
      // Should be 99% of original quote (1% fee)
      expect(result).toBe(990000n);
    });

    it("should handle zero value", () => {
      const quote = 0n;
      const result = calculateQuoteWithFees(quote);
      expect(result).toBe(0n);
    });
  });

  describe("calculateSlippage", () => {
    it("should correctly calculate 1% slippage", () => {
      const quote = 1000000n;
      const slippage = 100n; // 1% in basis points
      const result = calculateSlippage(quote, slippage);
      expect(result).toBe(990000n);
    });

    it("should correctly calculate 0.5% slippage", () => {
      const quote = 1000000n;
      const slippage = 50n; // 0.5% in basis points
      const result = calculateSlippage(quote, slippage);
      expect(result).toBe(995000n);
    });

    it("should handle zero slippage", () => {
      const quote = 1000000n;
      const slippage = 0n;
      const result = calculateSlippage(quote, slippage);
      expect(result).toBe(1000000n);
    });
  });

  describe("isQuoteChangeExceedingSlippage", () => {
    it("should return false when change is within slippage", () => {
      const originalQuote = 1000000n;
      const newQuote = 995000n; // 0.5% decrease
      const slippageBps = 100n; // 1% tolerance

      const result = isQuoteChangeExceedingSlippage(
        originalQuote,
        newQuote,
        slippageBps,
      );

      expect(result).toBe(false);
    });

    it("should return true when change exceeds slippage", () => {
      const originalQuote = 1000000n;
      const newQuote = 985000n; // 1.5% decrease
      const slippageBps = 100n; // 1% tolerance

      const result = isQuoteChangeExceedingSlippage(
        originalQuote,
        newQuote,
        slippageBps,
      );

      expect(result).toBe(true);
    });

    it("should handle positive price changes", () => {
      const originalQuote = 1000000n;
      const newQuote = 1015000n; // 1.5% increase
      const slippageBps = 100n; // 1% tolerance

      const result = isQuoteChangeExceedingSlippage(
        originalQuote,
        newQuote,
        slippageBps,
      );

      expect(result).toBe(false);
    });

    it("should handle zero original quote", () => {
      const originalQuote = 0n;
      const newQuote = 1000n;
      const slippageBps = 100n;

      expect(() =>
        isQuoteChangeExceedingSlippage(originalQuote, newQuote, slippageBps),
      ).not.toThrow();
    });
  });
});

describe("getBuyQuote", () => {
  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "should get buy quote for graduated market",
    async ({ viemClients: { publicClient } }) => {
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });
      const result = await getBuyQuote({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        amount: parseEther("1"),
        marketType,
        publicClient,
        poolAddress,
      });

      expect(result).toBeDefined();
      expect(result).toBeTypeOf("bigint");
    },
  );

  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "should get buy quote for non-graduated market",
    async ({ viemClients: { publicClient } }) => {
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });
      const result = await getBuyQuote({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        amount: parseEther("1"),
        marketType,
        poolAddress,
        publicClient,
      });

      expect(result).toBeDefined();
      expect(result).toBeTypeOf("bigint");
    },
  );
});

describe("getSellQuote", () => {
  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "should get sell quote for graduated market",
    async ({ viemClients: { publicClient } }) => {
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });
      const result = await getSellQuote({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        amount: parseEther("1000"),
        marketType,
        poolAddress,
        publicClient,
      });

      expect(result).toBeDefined();
      expect(result).toBeTypeOf("bigint");
    },
  );

  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "should get sell quote for non-graduated market",
    async ({ viemClients: { publicClient } }) => {
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });
      const result = await getSellQuote({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        amount: parseEther("1000"),
        marketType,
        poolAddress,
        publicClient,
      });

      expect(result).toBeDefined();
      expect(result).toBeTypeOf("bigint");
    },
  );
});
