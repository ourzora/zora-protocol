import { apiGet } from "@zoralabs/coins-sdk";

export const VALID_INTERVALS = ["1h", "24h", "1w", "1m", "ALL"] as const;
export type Interval = (typeof VALID_INTERVALS)[number];

export const INTERVAL_TO_API_FIELD: Record<Interval, string> = {
  "1h": "oneHour",
  "24h": "oneDay",
  "1w": "oneWeek",
  "1m": "oneMonth",
  ALL: "all",
};

type ApiPricePoint = { timestamp: string; closePrice: string };

export type PricePoint = { timestamp: string; price: number };

export const formatPrice = (price: number): string => {
  if (price >= 1) {
    return `$${price.toFixed(2)}`;
  }
  if (price >= 0.01) {
    return `$${price.toFixed(4)}`;
  }
  return `$${price.toPrecision(4)}`;
};

export const formatChange = (
  first: number,
  last: number,
): { text: string; color: "green" | "red" | undefined } => {
  if (first === 0) return { text: "-", color: undefined };
  const pct = ((last - first) / first) * 100;
  const prefix = pct >= 0 ? "+" : "";
  const text = `${prefix}${pct.toFixed(1)}%`;
  const color: "green" | "red" | undefined =
    pct > 0 ? "green" : pct < 0 ? "red" : undefined;
  return { text, color };
};

export const fetchPriceHistory = async (
  address: string,
  interval: Interval,
): Promise<PricePoint[]> => {
  const response = await apiGet("/coinPriceHistory", {
    address,
  });

  const data = response.data as
    | {
        zora20Token?: Record<string, ApiPricePoint[] | undefined> | null;
      }
    | undefined;

  const token = data?.zora20Token;
  if (!token) return [];

  const field = INTERVAL_TO_API_FIELD[interval];
  const points = token[field];
  if (!points || points.length === 0) return [];

  return points.map((p) => ({
    timestamp: p.timestamp,
    price: Number(p.closePrice),
  }));
};
