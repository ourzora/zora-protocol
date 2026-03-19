import { format, formatDistanceStrict } from "date-fns";
import { formatEther } from "viem";

export function formatCurrency(value: string | undefined): string {
  if (!value || Number(value) === 0) return "$0";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    notation: "compact",
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  }).format(Number(value));
}

type ChangeColor = "green" | "red" | undefined;
const NO_CHANGE = { text: "-", color: undefined } as const;

export function formatMcapChange(
  marketCap: string | undefined,
  delta: string | undefined,
): { text: string; color: ChangeColor } {
  if (!delta || !marketCap) return NO_CHANGE;

  const currentMCap = Number(marketCap);
  const absoluteDelta = Number(delta);
  const previousMCap = currentMCap - absoluteDelta;

  if (currentMCap === 0 || previousMCap === 0) return NO_CHANGE;

  const percentChange = (absoluteDelta / previousMCap) * 100;
  const plusPrefix = percentChange >= 0 ? "+" : "";
  const text = `${plusPrefix}${percentChange.toFixed(1)}%`;
  const color: ChangeColor =
    percentChange > 0 ? "green" : percentChange < 0 ? "red" : undefined;

  return { text, color };
}

export function formatUsd(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function truncate(str: string, max: number): string {
  if (str.length <= max) return str;
  return str.slice(0, max - 1) + "\u2026";
}

export function formatHolders(count: number): string {
  return new Intl.NumberFormat("en-US").format(count);
}

export function formatRelativeTime(date: Date, now: Date = new Date()): string {
  const diffMs = now.getTime() - date.getTime();
  if (diffMs < 60_000) return "just now";
  return formatDistanceStrict(date, now, { addSuffix: true });
}

export function formatAbsoluteTime(date: Date): string {
  return format(date, "yyyy-MM-dd h:mm a");
}

export function formatCreatedAt(
  isoDate: string | undefined,
  now?: Date,
): string {
  if (!isoDate) return "-";
  const date = new Date(isoDate);
  if (isNaN(date.getTime())) return "-";
  return `${formatRelativeTime(date, now)} (${formatAbsoluteTime(date)})`;
}

export const formatEthDisplay = (wei: bigint): string => {
  const eth = formatEther(wei);
  const parts = eth.split(".");
  if (!parts[1]) return eth;
  const trimmed = parts[1].replace(/0+$/, "") || "0";
  return `${parts[0]}.${trimmed}`;
};

export const formatCoinsDisplay = (coinsOut: string): string =>
  new Intl.NumberFormat("en-US", {
    maximumFractionDigits: 2,
  }).format(Number(coinsOut));
