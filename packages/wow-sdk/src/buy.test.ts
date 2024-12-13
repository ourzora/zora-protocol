import {
  forkUrls,
  makeAnvilTest,
  waitForTransactionReceiptWithRetries,
} from "./test";
import { describe } from "node:test";
import { base } from "viem/chains";
import { expect } from "vitest";
import { parseEther } from "viem";
import { buyTokens } from "./buy";
import { getBuyQuote } from "./quote";
import { getMarketTypeAndPoolAddress } from "./utils/transaction";

describe("buy wow token", () => {
  makeAnvilTest({
    forkBlockNumber: 23589888,
    forkUrl: forkUrls.baseMainnet,
    anvilChainId: base.id,
  })(
    "can buy token",
    async ({ viemClients: { publicClient, walletClient } }) => {
      const tokenAddress = "0x01aa2894773c091cc21a8880b3633ac173727440";
      const ethAmount = "1";
      const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
        tokenAddress,
        publicClient,
      });
      const quote = await getBuyQuote({
        chainId: base.id,
        publicClient,
        tokenAddress,
        amount: parseEther(ethAmount),
        marketType,
        poolAddress,
      });

      const hash = await buyTokens({
        chainId: base.id,
        tokenRecipientAddress: walletClient.account?.address!,
        tokenAddress,
        refundRecipientAddress: walletClient.account?.address!,
        originalTokenQuote: quote,
        slippageBps: 100n,
        ethAmount,
        publicClient,
        walletClient,
      });

      const receipt = await waitForTransactionReceiptWithRetries(
        publicClient,
        hash,
      );

      expect(receipt.status).toBe("success");
    },

    20_000,
  );
});
