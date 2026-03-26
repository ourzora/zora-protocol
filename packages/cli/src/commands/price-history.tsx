import { Command } from "commander";
import { setApiKey, apiGet } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { getJson, outputErrorAndExit, outputData } from "../lib/output.js";
import { parseCoinRef, resolveCoin } from "../lib/coin-ref.js";
import { renderOnce } from "../lib/render.js";
import { PriceHistory } from "../components/PriceHistory.js";
import {
  sparkline,
  downsample,
  MAX_SPARKLINE_WIDTH,
} from "../lib/sparkline.js";
import { track } from "../lib/analytics.js";
import type { CoinType } from "../lib/types.js";

const VALID_TYPES: readonly CoinType[] = ["creator-coin", "post", "trend"];

const VALID_INTERVALS = ["1h", "24h", "1w", "1m", "ALL"] as const;
type Interval = (typeof VALID_INTERVALS)[number];

const INTERVAL_TO_API_FIELD: Record<Interval, string> = {
  "1h": "oneHour",
  "24h": "oneDay",
  "1w": "oneWeek",
  "1m": "oneMonth",
  ALL: "all",
};

type ApiPricePoint = { timestamp: string; closePrice: string };

type PricePoint = { timestamp: string; price: number };

const formatPrice = (price: number): string => {
  if (price >= 1) {
    return `$${price.toFixed(2)}`;
  }
  if (price >= 0.01) {
    return `$${price.toFixed(4)}`;
  }
  return `$${price.toPrecision(4)}`;
};

const formatChange = (
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

const fetchPriceHistory = async (
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

export const priceHistoryCommand = new Command("price-history")
  .description("Display price history for a coin")
  .argument("[identifier]", "Coin address (0x...) or name")
  .option("--type <type>", "Coin type: creator-coin, post, trend")
  .option(
    "--interval <interval>",
    `Time range: ${VALID_INTERVALS.join(", ")}`,
    "1w",
  )
  .action(async function (
    this: Command,
    identifier: string,
    opts: { type?: string; interval?: string },
  ) {
    const json = getJson(this);
    const interval = (opts.interval ?? "1w") as string;

    if (!VALID_INTERVALS.includes(interval as Interval)) {
      outputErrorAndExit(
        json,
        `Invalid --interval value: ${interval}.`,
        `Supported: ${VALID_INTERVALS.join(", ")}`,
      );
    }

    if (opts.type !== undefined && !VALID_TYPES.includes(opts.type as any)) {
      outputErrorAndExit(
        json,
        `Invalid --type value: ${opts.type}.`,
        `Supported: ${VALID_TYPES.join(", ")}`,
      );
    }

    if (opts.type === "post" && !identifier.startsWith("0x")) {
      outputErrorAndExit(
        json,
        "Posts can only be looked up by address.",
        "Use: zora price-history 0x...",
      );
    }

    const ref = parseCoinRef(identifier, opts.type);

    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

    let result;
    try {
      result = await resolveCoin(ref);
    } catch (err) {
      outputErrorAndExit(
        json,
        `Request failed: ${err instanceof Error ? err.message : String(err)}`,
      );
      return;
    }

    if (result.kind === "not-found") {
      outputErrorAndExit(json, result.message, result.suggestion);
      return;
    }

    const { coin } = result;

    let prices: PricePoint[];
    try {
      prices = await fetchPriceHistory(coin.address, interval as Interval);
    } catch (err) {
      outputErrorAndExit(
        json,
        `Failed to fetch price data: ${err instanceof Error ? err.message : String(err)}`,
      );
      return;
    }

    if (prices.length === 0) {
      outputErrorAndExit(
        json,
        `No price data found for ${coin.name} in the last ${interval}.`,
        "Try a longer interval with --interval",
      );
      return;
    }

    const priceValues = prices.map((p) => p.price);
    const high = Math.max(...priceValues);
    const low = Math.min(...priceValues);
    const change = formatChange(
      priceValues[0],
      priceValues[priceValues.length - 1],
    );
    const sparklineText = sparkline(
      downsample(priceValues, MAX_SPARKLINE_WIDTH),
    );

    outputData(json, {
      json: {
        coin: coin.name,
        type: coin.coinType,
        interval,
        high,
        low,
        change:
          priceValues[0] === 0
            ? null
            : (priceValues[priceValues.length - 1] - priceValues[0]) /
              priceValues[0],
        prices: prices.map((p) => ({
          timestamp: p.timestamp,
          price: p.price,
        })),
      },
      render: () => {
        renderOnce(
          <PriceHistory
            coin={coin.name}
            coinType={coin.coinType}
            interval={interval}
            high={formatPrice(high)}
            low={formatPrice(low)}
            change={change}
            sparklineText={sparklineText}
          />,
        );
      },
    });

    track("cli_price_history", {
      lookup_type: identifier.startsWith("0x") ? "address" : "name",
      coin_type: coin.coinType,
      interval,
      data_points: prices.length,
      output_format: json ? "json" : "text",
    });
  });
