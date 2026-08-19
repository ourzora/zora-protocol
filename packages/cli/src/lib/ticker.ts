/**
 * Ticker (coin symbol) constraints, mirroring the limits the Zora web app
 * enforces (TrendCoinTickerSchema): 2–20 characters, letters and numbers only.
 * The CLI bypasses the web form, so we validate here to reject the same inputs
 * the app would refuse rather than submitting a coin that fails downstream.
 */
export const TICKER_MIN_LENGTH = 2;
export const TICKER_MAX_LENGTH = 20;
export const TICKER_PATTERN = /^[A-Za-z0-9]+$/;

/**
 * Validate a user-supplied ticker. Returns a human-readable error message when
 * invalid, or `undefined` when valid. Callers decide how to surface it
 * (`outputErrorAndExit` in the command layer, `throw` in library code).
 */
export function validateTicker(ticker: string): string | undefined {
  const value = ticker.trim();
  if (value.length < TICKER_MIN_LENGTH) {
    return `Ticker must be at least ${TICKER_MIN_LENGTH} characters.`;
  }
  if (value.length > TICKER_MAX_LENGTH) {
    return `Ticker must be ${TICKER_MAX_LENGTH} characters or fewer (got ${value.length}).`;
  }
  if (!TICKER_PATTERN.test(value)) {
    return "Ticker must use only letters and numbers (A–Z, 0–9) — no spaces or punctuation.";
  }
  return undefined;
}
