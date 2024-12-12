import { Address, parseEther, zeroAddress } from "viem";
import { WowERC20ABI } from "./abi/WowERC20";
import { getBuyQuote } from "./quote";
import { WowTransactionBaseArgs } from "./types";
import {
  calculateSlippage,
  isQuoteChangeExceedingSlippage,
} from "./utils/quote";
import { calculateQuoteWithFees } from "./utils/quote";
import { SlippageExceededError } from "./errors";
import { getMarketTypeAndPoolAddress } from "./utils/transaction";

export interface BuyWowTokenArgs extends WowTransactionBaseArgs {
  /**
   * Refund recipient address
   */
  refundRecipientAddress: Address;
  /**
   * Amount of ETH to buy
   */
  ethAmount: string;
}

/**
 * Simulates and executes a transaction to buy Wow tokens on the given WalletClient.
 * For more details on Wow mechanis, see https://wow.xyz/mechanics
 * @returns
 * @throws {NoPoolAddressFoundError}
 * @throws {SlippageExceededError}
 */
export async function buyTokens(args: BuyWowTokenArgs) {
  const {
    chainId,
    publicClient,
    walletClient,
    tokenAddress,
    tokenRecipientAddress,
    refundRecipientAddress,
    originalTokenQuote,
    slippageBps,
    ethAmount,
    poolAddress: passedInPoolAddress,
    comment = "",
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
  const updatedTokenQuote = await getBuyQuote({
    chainId,
    tokenAddress,
    amount: parseEther(ethAmount),
    poolAddress,
    marketType,
    publicClient,
  });

  console.log({ originalTokenQuote, updatedTokenQuote });
  if (
    isQuoteChangeExceedingSlippage(
      originalTokenQuote,
      updatedTokenQuote,
      slippageBps,
    )
  ) {
    throw new SlippageExceededError(originalTokenQuote, updatedTokenQuote);
  }

  const { request } = await publicClient.simulateContract({
    address: tokenAddress,
    abi: WowERC20ABI,
    functionName: "buy",
    args: [
      tokenRecipientAddress,
      refundRecipientAddress,
      referrerAddress,
      comment,
      marketType,
      calculateSlippage(
        calculateQuoteWithFees(originalTokenQuote),
        slippageBps,
      ),
      0n,
    ],
    value: parseEther(ethAmount),
    account: walletClient.account?.address,
  });

  // Bump up the gas as due to the graduation logic, some wallets have issues with the gas limit
  const requestWithExtraGas = {
    ...request,
    gas: request.gas ? (request.gas * 13n) / 10n : undefined,
  };

  const hash = await walletClient.writeContract(requestWithExtraGas);

  return hash;
}
