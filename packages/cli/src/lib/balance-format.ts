import { formatUsd } from "./format.js";

const COIN_DECIMALS = 18;

export const parseRawBalance = (rawBalance: string): number =>
  Number(normalizeTokenAmount(rawBalance));

export const normalizeTokenAmount = (
  rawBalance: string,
  decimals = COIN_DECIMALS,
): string => {
  try {
    const value = BigInt(rawBalance);
    const divisor = 10n ** BigInt(decimals);
    const whole = value / divisor;
    const fraction = value % divisor;

    if (fraction === 0n) return whole.toString();

    const fractionText = fraction
      .toString()
      .padStart(decimals, "0")
      .replace(/0+$/, "");
    return `${whole}.${fractionText}`;
  } catch {
    console.warn(`Warning: could not parse token amount "${rawBalance}"`);
    return rawBalance;
  }
};

/**
 * Compute the USD value of a coin balance.
 *
 * When a pre-computed `marketValueUsd` is available (from SDK valuation),
 * it is preferred. Otherwise the value is derived from the raw token
 * balance and the per-token price.
 *
 * Returns `null` when no value can be determined.
 */
export const computeBalanceUsdValue = (
  balance: string,
  marketValueUsd?: string,
  priceInUsdc?: string,
): number | null => {
  if (marketValueUsd != null && marketValueUsd !== "") {
    const parsed = Number(marketValueUsd);
    if (!Number.isFinite(parsed)) return null;
    return Number(parsed.toFixed(6));
  }

  if (!priceInUsdc) return null;
  const price = Number(priceInUsdc);
  if (!Number.isFinite(price)) return null;

  const value = parseRawBalance(balance) * price;
  return Number(value.toFixed(6));
};

export const formatBalanceAsUsd = (
  balance: string,
  priceInUsdc?: string,
): string => {
  const value = computeBalanceUsdValue(balance, undefined, priceInUsdc);
  if (value === null) return "-";
  if (value < 0.01) return "<$0.01";
  return formatUsd(value);
};

export const formatBalance = (balance: string): string => {
  const n = parseRawBalance(balance);
  if (n === 0) return "0";
  if (n < 0.001) return "<0.001";
  if (n < 1) return n.toFixed(4);
  return new Intl.NumberFormat("en-US", {
    notation: "compact",
    compactDisplay: "short",
    maximumFractionDigits: 1,
  }).format(n);
};

export const trimTrailingZeros = (value: string): string => {
  if (!value.includes(".")) return value;
  const trimmed = value.replace(/0+$/, "").replace(/\.$/, "");
  return trimmed || "0";
};
