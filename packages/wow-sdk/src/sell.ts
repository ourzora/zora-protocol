import { zeroAddress } from "viem";
import { WowERC20ABI } from "./abi/WowERC20";
import { WowTransactionBaseArgs } from "./types";
import { calculateSlippage } from "./utils/quote";
import { isQuoteChangeExceedingSlippage } from "./utils/quote";
import { getSellQuote } from "./quote";
import { SlippageExceededError } from "./errors";
import { getMarketTypeAndPoolAddress } from "./utils/transaction";

export interface SellWowTokenArgs extends WowTransactionBaseArgs {
  /**
   * Amount of Wow tokens to sell
   */
  tokenAmount: bigint;
}

/**
 * Simulates and executes a transaction to sell Wow tokens on the given WalletClient.
 * For more details on Wow mechanis, see https://wow.xyz/mechanics
 * @throws {NoPoolAddressFoundError}
 * @throws {SlippageExceededError}
 */
export async function sellTokens(args: SellWowTokenArgs) {
  const {
    chainId,
    publicClient,
    walletClient,
    tokenAddress,
    tokenRecipientAddress,
    poolAddress: passedInPoolAddress,
    tokenAmount,
    comment = "",
    originalTokenQuote,
    slippageBps,
    referrerAddress = zeroAddress,
  } = args;

  const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
    tokenAddress,
    publicClient,
    poolAddress: passedInPoolAddress,
  });

  /**
   * Get the quote again in case it has changed since the consumer fetched it
   */
  const updatedQuote = await getSellQuote({
    chainId,
    publicClient,
    tokenAddress,
    amount: tokenAmount,
    poolAddress,
    marketType,
  });

  if (
    isQuoteChangeExceedingSlippage(
      originalTokenQuote,
      updatedQuote,
      slippageBps,
    )
  ) {
    throw new SlippageExceededError(originalTokenQuote, updatedQuote);
  }

  const { request } = await publicClient.simulateContract({
    address: tokenAddress,
    abi: WowERC20ABI,
    functionName: "sell",
    args: [
      tokenAmount,
      tokenRecipientAddress,
      referrerAddress,
      comment,
      marketType,
      calculateSlippage(updatedQuote, slippageBps),
      0n,
    ],
    account: walletClient.account?.address,
  });

  const hash = await walletClient.writeContract(request);

  return hash;
}
