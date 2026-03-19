import { formatUsd } from "./format.js";

const COIN_DECIMALS = 18;

export const toHumanBalance = (rawBalance: string): number =>
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

export const formatUsdValue = (
  balance: string,
  priceInUsdc?: string,
): string => {
  if (!priceInUsdc) return "-";
  const value = toHumanBalance(balance) * Number(priceInUsdc);
  if (value < 0.01) return "<$0.01";
  return formatUsd(value);
};

export const formatBalance = (balance: string): string => {
  const n = toHumanBalance(balance);
  if (n === 0) return "0";
  if (n < 0.001) return "<0.001";
  if (n < 1) return n.toFixed(4);
  return new Intl.NumberFormat("en-US", {
    notation: "compact",
    compactDisplay: "long",
    maximumFractionDigits: 1,
  }).format(n);
};

export const trimTrailingZeros = (value: string): string => {
  if (!value.includes(".")) return value;
  const trimmed = value.replace(/0+$/, "").replace(/\.$/, "");
  return trimmed || "0";
};
