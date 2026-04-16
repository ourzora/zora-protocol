import { Command } from "commander";
import { Box, Text } from "ink";
import { setApiKey } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import {
  getJson,
  getOutputMode,
  getLiveConfig,
  outputErrorAndExit,
  outputData,
} from "../lib/output.js";
import {
  parsePositionalCoinArgs,
  coinArgsToRef,
  resolveAmbiguousName,
  resolveCoin,
  formatAmbiguousError,
  CoinArgError,
  type ResolvedCoin,
} from "../lib/coin-ref.js";
import { renderOnce, renderLive } from "../lib/render.js";
import { CoinDetail } from "../components/CoinDetail.js";
import { PriceHistory } from "../components/PriceHistory.js";
import { CoinView, type CoinViewData } from "../components/CoinView.js";
import {
  VALID_INTERVALS,
  type Interval,
  fetchPriceHistory,
  formatPrice,
  formatChange,
} from "../lib/price-history.js";
import {
  sparkline,
  downsample,
  MAX_SPARKLINE_WIDTH,
} from "../lib/sparkline.js";
import { track } from "../lib/analytics.js";
import { bannedCoinMessage } from "../lib/errors.js";

// --- Shared helpers ---

function formatCoinJson(coin: ResolvedCoin): Record<string, unknown> {
  return {
    name: coin.name,
    address: coin.address,
    coinType: coin.coinType,
    marketCap: coin.marketCap,
    marketCapDelta24h: coin.marketCapDelta24h,
    volume24h: coin.volume24h,
    uniqueHolders: coin.uniqueHolders,
    createdAt: coin.createdAt ?? null,
    creatorAddress: coin.creatorAddress ?? null,
    creatorHandle: coin.creatorHandle ?? null,
  };
}

const resolveApiKey = () => {
  const apiKey = getApiKey();
  if (apiKey) {
    setApiKey(apiKey);
  }
};

class CoinResolutionError extends Error {
  suggestion?: string;
  constructor(message: string, suggestion?: string) {
    super(message);
    this.suggestion = suggestion;
  }
}

type CoinResolution = {
  coin: ResolvedCoin;
  lookupType: string;
  coinTypeFilter: string | null;
};

async function resolveCoinOrThrow(
  typeOrId: string,
  identifier: string | undefined,
  command: string,
): Promise<CoinResolution> {
  const parsed = parsePositionalCoinArgs(typeOrId, identifier);

  resolveApiKey();

  if (parsed.kind === "ambiguous-name") {
    const ambResult = await resolveAmbiguousName(parsed.name);

    if (ambResult.kind === "not-found") {
      throw new Error(ambResult.message);
    }

    if (ambResult.kind === "ambiguous") {
      const { message, suggestion } = formatAmbiguousError(
        parsed.name,
        ambResult.creator,
        ambResult.trend,
        command,
      );
      throw new CoinResolutionError(message, suggestion);
    }

    return {
      coin: ambResult.coin,
      lookupType: "name",
      coinTypeFilter: null,
    };
  }

  const ref = coinArgsToRef(parsed);
  const result = await resolveCoin(ref);

  if (result.kind === "not-found") {
    throw new CoinResolutionError(result.message, result.suggestion);
  }

  if (result.coin.platformBlocked) {
    throw new Error(bannedCoinMessage(result.coin.address));
  }

  return {
    coin: result.coin,
    lookupType: typeOrId.startsWith("0x") ? "address" : "name",
    coinTypeFilter: parsed.kind === "typed" ? parsed.type : null,
  };
}

async function resolveAndValidateCoin(
  json: boolean,
  typeOrId: string,
  identifier: string | undefined,
  command: string,
): Promise<CoinResolution> {
  try {
    return await resolveCoinOrThrow(typeOrId, identifier, command);
  } catch (err) {
    if (err instanceof CoinArgError) {
      outputErrorAndExit(json, err.message, err.suggestion);
    }
    if (err instanceof CoinResolutionError) {
      outputErrorAndExit(json, err.message, err.suggestion);
    }
    const msg = err instanceof Error ? err.message : String(err);
    outputErrorAndExit(json, msg);
  }
}

async function buildPriceHistoryData(
  address: string,
  interval: Interval,
): Promise<CoinViewData["priceHistory"]> {
  let prices;
  try {
    prices = await fetchPriceHistory(address, interval);
  } catch {
    return null;
  }

  if (prices.length === 0) return null;

  const priceValues = prices.map((p) => p.price);
  const high = Math.max(...priceValues);
  const low = Math.min(...priceValues);
  const change = formatChange(
    priceValues[0],
    priceValues[priceValues.length - 1],
  );
  const sparklineText = sparkline(downsample(priceValues, MAX_SPARKLINE_WIDTH));

  return {
    high: formatPrice(high),
    low: formatPrice(low),
    change,
    sparklineText,
    interval,
  };
}

// --- Main get command ---

export const getCommand = new Command("get")
  .description("Look up a coin by address or name")
  .argument("[typeOrId]", "Type prefix (creator-coin, trend) or identifier")
  .argument(
    "[identifier]",
    "Coin address (0x...) or name (when type prefix is given)",
  )
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .action(async function (
    this: Command,
    typeOrId: string,
    identifier: string | undefined,
  ) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    const interval: Interval = "1w";

    const { coin, lookupType, coinTypeFilter } = await resolveAndValidateCoin(
      json,
      typeOrId,
      identifier,
      "get",
    );

    if (json) {
      let prices;
      try {
        prices = await fetchPriceHistory(coin.address, interval as Interval);
      } catch {
        prices = [];
      }

      outputData(json, {
        json: {
          ...formatCoinJson(coin),
          priceHistory:
            prices.length > 0
              ? {
                  interval,
                  high: Math.max(...prices.map((p) => p.price)),
                  low: Math.min(...prices.map((p) => p.price)),
                  change:
                    prices[0].price === 0
                      ? null
                      : (prices[prices.length - 1].price - prices[0].price) /
                        prices[0].price,
                  prices: prices.map((p) => ({
                    timestamp: p.timestamp,
                    price: p.price,
                  })),
                }
              : null,
        },
        render: () => {},
      });

      track("cli_get", {
        lookup_type: lookupType,
        coin_type_filter: coinTypeFilter,
        coin_type: coin.coinType,
        output_format: "json",
      });
      return;
    }

    const { live, intervalSeconds } = getLiveConfig(this, output);

    if (live) {
      const initialPriceHistory = await buildPriceHistoryData(
        coin.address,
        interval as Interval,
      );

      const fetchData = async (): Promise<CoinViewData> => {
        const { coin: freshCoin } = await resolveCoinOrThrow(
          typeOrId,
          identifier,
          "get",
        );
        const priceHistory = await buildPriceHistoryData(
          freshCoin.address,
          interval as Interval,
        );
        return { coin: freshCoin, priceHistory };
      };

      await renderLive(
        <CoinView
          fetchData={fetchData}
          initialData={{ coin, priceHistory: initialPriceHistory }}
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
        />,
      );

      track("cli_get", {
        lookup_type: lookupType,
        coin_type_filter: coinTypeFilter,
        coin_type: coin.coinType,
        output_format: "live",
        interval: intervalSeconds,
      });
    } else {
      const priceHistory = await buildPriceHistoryData(
        coin.address,
        interval as Interval,
      );

      renderOnce(
        <Box flexDirection="column">
          <CoinDetail coin={coin} />
          {priceHistory ? (
            <PriceHistory
              coin={coin.name}
              coinType={coin.coinType}
              interval={priceHistory.interval}
              high={priceHistory.high}
              low={priceHistory.low}
              change={priceHistory.change}
              sparklineText={priceHistory.sparklineText}
              compact
            />
          ) : (
            <Box paddingLeft={1} paddingBottom={1}>
              <Text dimColor>No price data available.</Text>
            </Box>
          )}
        </Box>,
      );

      track("cli_get", {
        lookup_type: lookupType,
        coin_type_filter: coinTypeFilter,
        coin_type: coin.coinType,
        output_format: "static",
      });
    }
  });

// --- price-history subcommand ---

getCommand
  .command("price-history")
  .description("Display price history for a coin")
  .argument("[typeOrId]", "Type prefix (creator-coin, trend) or identifier")
  .argument(
    "[identifier]",
    "Coin address (0x...) or name (when type prefix is given)",
  )
  .option(
    "--interval <interval>",
    `Time range: ${VALID_INTERVALS.join(", ")}`,
    "1w",
  )
  .action(async function (
    this: Command,
    typeOrId: string,
    identifier: string | undefined,
    opts: { interval?: string },
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

    const { coin, lookupType } = await resolveAndValidateCoin(
      json,
      typeOrId,
      identifier,
      "get price-history",
    );

    let prices;
    try {
      prices = await fetchPriceHistory(coin.address, interval as Interval);
    } catch (err) {
      outputErrorAndExit(
        json,
        `Failed to fetch price data: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    if (prices.length === 0) {
      outputErrorAndExit(
        json,
        `No price data found for ${coin.name} in the last ${interval}.`,
        "Try a longer interval with --interval",
      );
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
        coinType: coin.coinType,
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

    track("cli_get_price_history", {
      lookup_type: lookupType,
      coin_type: coin.coinType,
      interval,
      data_points: prices.length,
      output_format: json ? "json" : "text",
    });
  });
