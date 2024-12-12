/**
 * Calculate the quote taking into account the 1% transaction fee
 */
export const calculateQuoteWithFees = (quote: bigint) =>
  (quote * 9900n) / 10000n;

// Fee percentage is in basis points (1/100th of a percent)
export const calculateSlippage = (quote: bigint, feePercentage: bigint) =>
  (quote * (10000n - feePercentage)) / 10000n;

/**
 * Checks if the difference between two quotes exceeds the allowed slippage
 * @param originalQuote The original quote amount
 * @param newQuote The new quote amount
 * @param slippageBps The allowed slippage in basis points (e.g., 100 = 1%)
 * @returns true if slippage is exceeded, false otherwise
 */
export function isQuoteChangeExceedingSlippage(
  originalQuote: bigint,
  newQuote: bigint,
  slippageBps: bigint,
): boolean {
  // Convert slippage from basis points to decimal (e.g., 100bps = 0.01)
  const slippageThreshold = (Number(10000) - Number(slippageBps)) / 10000;

  // Calculate the ratio of change
  const quoteDiff = Number((newQuote - originalQuote) / originalQuote);

  // Return true if the absolute difference exceeds the threshold
  return Math.abs(quoteDiff) > slippageThreshold;
}
