import {
  Address,
  ContractFunctionArgs,
  parseEther,
  SimulateContractParameters,
  zeroAddress,
} from "viem";
import { WowERC20ABI } from "./abi/WowERC20";
import { WowTransactionBaseArgs } from "./types";
import {
  calculateSlippage,
  isQuoteChangeExceedingSlippage,
  getBuyQuote,
  calculateQuoteWithFees,
} from "./quote";
import { NoQuoteFoundError, SlippageExceededError } from "./errors";
import { getMarketTypeAndPoolAddress } from "./pool/transaction";
import { SimulateContractParametersWithAccount } from "./test";

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
 * @throws {NoQuoteFoundError}
 */
export async function prepareTokenBuy(args: BuyWowTokenArgs) {
  const {
    publicClient,
    tokenAddress,
    tokenRecipientAddress,
    refundRecipientAddress,
    account,
    originalTokenQuote,
    slippageBps = 100n,
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
    tokenAddress,
    amount: parseEther(ethAmount),
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
    "buy",
    ContractFunctionArgs<typeof WowERC20ABI, "nonpayable" | "payable", "buy">,
    any,
    any,
    Address
  > = {
    address: tokenAddress,
    abi: WowERC20ABI,
    functionName: "buy" as const,
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
      0n, // Uniswap slippage param we don't use
    ] as const,
    value: parseEther(ethAmount),
    account,
  };

  return parameters as SimulateContractParametersWithAccount;
}
