import {
  Address,
  ContractFunctionArgs,
  PublicClient,
  Transport,
  SimulateContractParameters,
  zeroAddress,
} from "viem";
import { WowERC20ABI } from "./abi/WowERC20";
import { SupportedChain, WowTransactionBaseArgs } from "./types";
import {
  calculateSlippage,
  isQuoteChangeExceedingSlippage,
  getSellQuote,
} from "./quote";
import { NoQuoteFoundError, SlippageExceededError } from "./errors";
import { getMarketTypeAndPoolAddress } from "./pool/transaction";

export interface SellWowTokenArgs extends WowTransactionBaseArgs {
  /**
   * Amount of tokens to sell
   */
  tokenAmount: bigint;
}

/**
 * Simulates and executes a transaction to sell Wow tokens on the given WalletClient.
 * For more details on Wow mechanics, see https://wow.xyz/mechanics
 * @returns
 * @throws {NoPoolAddressFoundError}
 * @throws {SlippageExceededError}
 * @throws {NoQuoteFoundError}
 */
export async function prepareTokenSell(args: SellWowTokenArgs) {
  const {
    publicClient,
    account,
    tokenAddress,
    tokenRecipientAddress,
    originalTokenQuote,
    slippageBps = 100n,
    tokenAmount,
    poolAddress: passedInPoolAddress,
    comment = "",
    referrerAddress = zeroAddress,
  } = args;

  const { marketType, poolAddress } = await getMarketTypeAndPoolAddress({
    tokenAddress,
    publicClient: publicClient as PublicClient<Transport, SupportedChain>,
    poolAddress: passedInPoolAddress,
  });

  /**
   * Get the quote again in case it has changed since the consumer fetched it
   */
  const updatedTokenQuote = await getSellQuote({
    tokenAddress,
    amount: tokenAmount,
    poolAddress,
    marketType,
    publicClient,
  });

  if (!updatedTokenQuote) {
    throw new NoQuoteFoundError();
  }

  if (
    isQuoteChangeExceedingSlippage(
      originalTokenQuote,
      updatedTokenQuote,
      slippageBps,
    )
  ) {
    throw new SlippageExceededError(originalTokenQuote, updatedTokenQuote);
  }

  const parameters: SimulateContractParameters<
    typeof WowERC20ABI,
    "sell",
    ContractFunctionArgs<typeof WowERC20ABI, "nonpayable" | "payable", "sell">,
    any,
    any,
    Address
  > = {
    address: tokenAddress,
    abi: WowERC20ABI,
    functionName: "sell" as const,
    args: [
      tokenAmount,
      tokenRecipientAddress,
      referrerAddress,
      comment,
      marketType,
      calculateSlippage(originalTokenQuote, slippageBps),
      0n,
    ] as const,
    account,
  };

  return parameters;
}
