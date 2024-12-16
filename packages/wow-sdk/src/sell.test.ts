import { makeAnvilTest, simulateAndWriteContractWithRetries } from "./test";
import { describe } from "node:test";
import { base } from "viem/chains";
import { expect } from "vitest";
import { parseEther } from "viem";
import { buyTokens } from "./buy";
import { sellTokens } from "./sell";
import { getBuyQuote, getSellQuote } from "./quote";
import { getMarketTypeAndPoolAddress } from "./pool/transaction";
import { BASE_MAINNET_FORK_BLOCK_NUMBER, forkUrls } from "./test/constants";
import { SlippageExceededError } from "./errors";

describe("sell wow token", () => {
  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can buy and then sell token",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const tokenAddress = "0x01aa2894773c091cc21a8880b3633ac173727440";
      const ethAmount = "1";

      // First buy some tokens
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress,
        publicClient,
      });

      const buyQuote = await getBuyQuote({
        chainId: base.id,
        publicClient,
        tokenAddress,
        amount: parseEther(ethAmount),
        marketType,
        poolAddress,
      });
      const buyArgs = await buyTokens({
        chainId: base.id,
        publicClient,
        tokenAddress,
        tokenRecipientAddress: walletClient.account?.address!,
        refundRecipientAddress: walletClient.account?.address!,
        originalTokenQuote: buyQuote,
        slippageBps: 100n,
        ethAmount,
        account: walletClient.account?.address!,
      });

      const buyReceipt = await simulateAndWriteContractWithRetries({
        parameters: buyArgs,
        walletClient,
        publicClient,
      });

      expect(buyReceipt.status).toBe("success");

      // Now sell all tokens received, taking into account the 1% fee
      const tokenBalance = (buyQuote * 99n) / 100n;
      const sellQuote = await getSellQuote({
        chainId: base.id,
        publicClient,
        tokenAddress,
        amount: tokenBalance,
        marketType,
        poolAddress,
      });

      const sellArgs = await sellTokens({
        chainId: base.id,
        tokenRecipientAddress: walletClient.account?.address!,
        referrerAddress: walletClient.account?.address!,
        tokenAddress,
        originalTokenQuote: sellQuote,
        slippageBps: 100n,
        tokenAmount: tokenBalance,
        publicClient,
        account: walletClient.account?.address!,
      });

      const sellReceipt = await simulateAndWriteContractWithRetries({
        parameters: sellArgs,
        walletClient,
        publicClient,
      });

      expect(sellReceipt.status).toBe("success");
    },
    40_000, // Increased timeout since we're doing two transactions
  );

  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "throws SlippageExceededError when sell quote becomes stale",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const tokenAddress = "0x01aa2894773c091cc21a8880b3633ac173727440";
      const ethAmount = "5";

      // First buy a large amount of tokens
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress,
        publicClient,
      });

      const buyQuote = await getBuyQuote({
        chainId: base.id,
        publicClient,
        tokenAddress,
        amount: parseEther(ethAmount),
        marketType,
        poolAddress,
      });

      const buyArgs = await buyTokens({
        chainId: base.id,
        publicClient,
        tokenAddress,
        tokenRecipientAddress: walletClient.account?.address!,
        refundRecipientAddress: walletClient.account?.address!,
        originalTokenQuote: buyQuote,
        slippageBps: 100n,
        ethAmount,
        account: walletClient.account?.address!,
      });

      await simulateAndWriteContractWithRetries({
        parameters: buyArgs,
        walletClient,
        publicClient,
      });

      // Calculate token balance after 1% fee
      const totalTokenBalance = (buyQuote * 99n) / 100n;
      const halfTokenBalance = totalTokenBalance / 2n;

      // Get quote for selling half the tokens
      const sellQuote = await getSellQuote({
        chainId: base.id,
        publicClient,
        tokenAddress,
        amount: halfTokenBalance,
        marketType,
        poolAddress,
      });

      // Sell first half of tokens
      const sellArgs = await sellTokens({
        chainId: base.id,
        tokenRecipientAddress: walletClient.account?.address!,
        referrerAddress: walletClient.account?.address!,
        tokenAddress,
        originalTokenQuote: sellQuote,
        slippageBps: 100n,
        tokenAmount: halfTokenBalance,
        publicClient,
        account: walletClient.account?.address!,
      });

      await simulateAndWriteContractWithRetries({
        parameters: sellArgs,
        walletClient,
        publicClient,
      });

      // Try to sell second half using the same (now stale) quote
      await expect(
        sellTokens({
          chainId: base.id,
          tokenRecipientAddress: walletClient.account?.address!,
          referrerAddress: walletClient.account?.address!,
          tokenAddress,
          originalTokenQuote: sellQuote,
          slippageBps: 100n,
          tokenAmount: halfTokenBalance,
          publicClient,
          account: walletClient.account?.address!,
        }),
      ).rejects.toThrow(SlippageExceededError);
    },
    40_000,
  );
});
