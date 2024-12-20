import { makeAnvilTest, simulateAndWriteContractWithRetries } from "./test";
import { describe } from "node:test";
import { base } from "viem/chains";
import { expect } from "vitest";
import { parseEther } from "viem";
import { prepareTokenBuy } from "./buy";
import { getBuyQuote } from "./quote";
import { getMarketTypeAndPoolAddress } from "./pool/transaction";
import {
  BASE_GRADUATED_TOKEN_ADDRESS,
  BASE_MAINNET_FORK_BLOCK_NUMBER,
  forkUrls,
} from "./test/constants";
import { SlippageExceededError } from "./errors";

describe("buy wow token", () => {
  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can buy token",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const ethAmount = "1";
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });
      const quote = await getBuyQuote({
        publicClient,
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        amount: parseEther(ethAmount),
        marketType,
        poolAddress,
      });

      const params = await prepareTokenBuy({
        tokenRecipientAddress: walletClient.account?.address!,
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        refundRecipientAddress: walletClient.account?.address!,
        originalTokenQuote: quote,
        slippageBps: 100n,
        ethAmount,
        publicClient,
        account: walletClient.account?.address!,
      });
      const receipt = await simulateAndWriteContractWithRetries({
        parameters: params,
        walletClient,
        publicClient,
      });

      expect(receipt.status).toBe("success");
    },

    20_000,
  );

  makeAnvilTest({
    forkBlockNumber: BASE_MAINNET_FORK_BLOCK_NUMBER,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "throws SlippageExceededError when quote becomes stale",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        publicClient,
      });

      // Get initial quote for 1 ETH
      const staleQuote = await getBuyQuote({
        publicClient,
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        amount: parseEther("1"),
        marketType,
        poolAddress,
      });

      // Buy 5 ETH to significantly impact the price
      const largeAmount = "5";
      const largeQuote = await getBuyQuote({
        publicClient,
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        amount: parseEther(largeAmount),
        marketType,
        poolAddress,
      });

      const largeParams = await prepareTokenBuy({
        tokenRecipientAddress: walletClient.account?.address!,
        tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
        refundRecipientAddress: walletClient.account?.address!,
        originalTokenQuote: largeQuote,
        slippageBps: 100n,
        ethAmount: largeAmount,
        publicClient,
        account: walletClient.account?.address!,
      });

      // Execute the large buy to change the price
      await simulateAndWriteContractWithRetries({
        parameters: largeParams,
        walletClient,
        publicClient,
      });

      // Try to buy with the stale quote - should throw SlippageExceededError
      await expect(
        prepareTokenBuy({
          tokenRecipientAddress: walletClient.account?.address!,
          tokenAddress: BASE_GRADUATED_TOKEN_ADDRESS,
          refundRecipientAddress: walletClient.account?.address!,
          originalTokenQuote: staleQuote,
          slippageBps: 100n,
          ethAmount: "1",
          publicClient,
          account: walletClient.account?.address!,
        }),
      ).rejects.toThrow(SlippageExceededError);
    },
    30_000,
  );
});
