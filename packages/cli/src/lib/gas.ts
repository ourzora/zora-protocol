import { CoinbaseGasError } from "@zoralabs/coins-sdk";
import { Account, formatEther, parseEther } from "viem";

const DEFAULT_TOP_UP_AMOUNT = parseEther("0.001");

export const gasErrorSuggestion = (
  error: unknown,
  account: Account,
): string | undefined => {
  const isSmartWallet = account.type === "smart";
  const isGasError = error instanceof CoinbaseGasError;
  const walletAddress = account.address;

  if (isSmartWallet && isGasError) {
    const { required = 0n, available = 0n } = error;
    const missing = required - available > 0n ? required - available : 0n;
    // add 50% buffer to the missing amount (so gas price changes don't cause the operation to fail on the next attempt)
    const missingWithBuffer = (missing * 15n) / 10n;

    return missing > 0n
      ? `\nTop up your smart wallet (${walletAddress}) with at least ${formatEther(missingWithBuffer)} ETH to complete this operation (the amount suggested includes some buffer to account for gas price changes).`
      : `\nEnsure your smart wallet has enough ETH to cover gas fees. \nWe recommend topping up your smart wallet (${walletAddress}) with ${formatEther(DEFAULT_TOP_UP_AMOUNT)} ETH to ensure you have enough to cover fees for trading and posting.`;
  }
};
