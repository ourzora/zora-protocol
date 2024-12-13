import { makeAnvilTest, waitForTransactionReceiptWithRetries } from "./test";
import { describe } from "node:test";
import { base } from "viem/chains";
import { expect } from "vitest";
import { parseEther, TransactionReceipt } from "viem";
import { buyTokens } from "./buy";
import { sellTokens } from "./sell";
import { getBuyQuote, getSellQuote } from "./quote";
import { getMarketTypeAndPoolAddress } from "./pool/transaction";
import { BASE_MAINNET_FORK_BLOCK_NUMBER, forkUrls } from "./test/constants";

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

      const buyHash = await buyTokens({
        chainId: base.id,
        tokenRecipientAddress: walletClient.account?.address!,
        tokenAddress,
        refundRecipientAddress: walletClient.account?.address!,
        originalTokenQuote: buyQuote,
        slippageBps: 100n,
        ethAmount,
        publicClient,
        walletClient,
      });

      // Wait for buy transaction to complete
      let buyReceipt: TransactionReceipt | undefined;
      while (!buyReceipt) {
        try {
          buyReceipt = await publicClient.getTransactionReceipt({
            hash: buyHash,
          });
        } catch (e) {
          await new Promise((resolve) => setTimeout(resolve, 1000));
        }
      }
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

      const sellHash = await sellTokens({
        chainId: base.id,
        tokenRecipientAddress: walletClient.account?.address!,
        tokenAddress,
        originalTokenQuote: sellQuote,
        slippageBps: 100n,
        tokenAmount: tokenBalance,
        publicClient,
        walletClient,
      });

      // Wait for sell transaction to complete
      const sellReceipt = await waitForTransactionReceiptWithRetries(
        publicClient,
        sellHash,
      );
      expect(sellReceipt.status).toBe("success");
    },
    40_000, // Increased timeout since we're doing two transactions
  );
});
