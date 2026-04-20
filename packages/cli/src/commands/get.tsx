import { Command } from "commander";
import { Box, Text } from "ink";
import { setApiKey, getCoinHolders, getCoinSwaps } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import {
  getJson,
  getOutputMode,
  getLiveConfig,
  outputErrorAndExit,
  outputData,
} from "../lib/output.js";
import { Table } from "../components/table.js";
import { BASE_CHAIN_ID } from "../lib/constants.js";
import { formatBalance, parseRawBalance } from "../lib/balance-format.js";
import {
  parsePositionalCoinArgs,
  coinArgsToRef,
  resolveAmbiguousName,
  resolveCoin,
  formatAmbiguousError,
  CoinArgError,
  type ResolvedCoin,
} from "../lib/coin-ref.js";
import { truncateAddress } from "../lib/format.js";
import { renderOnce, renderLive } from "../lib/render.js";
import { CoinDetail } from "../components/CoinDetail.js";
import { PriceHistory } from "../components/PriceHistory.js";
import { CoinView, type CoinViewData } from "../components/CoinView.js";
import {
  CoinTradesView,
  coinTradeColumns,
  type TradeSwapNode,
} from "../components/CoinTradesView.js";
import type { PageResult } from "../components/PaginatedTableView.js";
import type { PageInfo } from "../lib/types.js";
import {
  CoinHoldersView,
  makeHolderColumns,
  type HolderNode,
} from "../components/CoinHoldersView.js";
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
import {
  apiErrorMessage,
  bannedCoinMessage,
  extractErrorMessage,
} from "../lib/errors.js";

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

async function fetchHoldersPageForCoin(
  address: string,
  count: number,
  after?: string,
): Promise<PageResult<HolderNode>> {
  const result = await getCoinHolders({
    chainId: BASE_CHAIN_ID,
    address,
    count,
    after,
  });

  const token = result.data?.zora20Token;
  if (!token) return { items: [] };

  const items: HolderNode[] = token.tokenBalances.edges.map((e) => ({
    balance: e.node.balance,
    ownerAddress: e.node.ownerAddress,
    ownerProfile:
      e.node.ownerProfile && !e.node.ownerProfile.platformBlocked
        ? { handle: e.node.ownerProfile.handle }
        : undefined,
  }));

  return {
    items,
    count: token.tokenBalances.count,
    pageInfo: token.tokenBalances.pageInfo,
  };
}

async function buildHoldersData(
  address: string,
): Promise<CoinViewData["holders"]> {
  try {
    const result = await fetchHoldersPageForCoin(address, 10);
    return {
      holders: result.items,
      totalCount: result.count ?? result.items.length,
    };
  } catch (err) {
    return {
      holders: [],
      totalCount: 0,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

async function fetchRecentTrades(address: string): Promise<TradeSwapNode[]> {
  try {
    const response = await getCoinSwaps({ address, first: 10 });
    const edges = response.data?.zora20Token?.swapActivities?.edges ?? [];
    return edges.map((e: { node: TradeSwapNode; cursor: string }) => e.node);
  } catch {
    return [];
  }
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
      const [prices, trades] = await Promise.all([
        fetchPriceHistory(coin.address, interval as Interval).catch(() => []),
        fetchRecentTrades(coin.address),
      ]);

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
          trades: trades.map((t) => ({
            type: t.activityType ?? null,
            sender: t.senderAddress,
            senderHandle: t.senderProfile?.handle ?? null,
            coinAmount: t.coinAmount,
            valueUsd: t.currencyAmountWithPrice.priceUsdc ?? null,
            timestamp: t.blockTimestamp,
            transactionHash: t.transactionHash,
          })),
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
      const [initialPriceHistory, initialTrades, initialHolders] =
        await Promise.all([
          buildPriceHistoryData(coin.address, interval as Interval),
          fetchRecentTrades(coin.address),
          buildHoldersData(coin.address),
        ]);

      const fetchData = async (): Promise<CoinViewData> => {
        const { coin: freshCoin } = await resolveCoinOrThrow(
          typeOrId,
          identifier,
          "get",
        );
        const [priceHistory, trades, holders] = await Promise.all([
          buildPriceHistoryData(freshCoin.address, interval as Interval),
          fetchRecentTrades(freshCoin.address),
          buildHoldersData(freshCoin.address),
        ]);
        return { coin: freshCoin, priceHistory, trades, holders };
      };

      await renderLive(
        <CoinView
          fetchData={fetchData}
          initialData={{
            coin,
            priceHistory: initialPriceHistory,
            trades: initialTrades,
            holders: initialHolders,
          }}
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
      const [priceHistory, trades] = await Promise.all([
        buildPriceHistoryData(coin.address, interval as Interval),
        fetchRecentTrades(coin.address),
      ]);

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
          {trades.length > 0 ? (
            <Table
              columns={coinTradeColumns.filter((c) => c.header !== "#")}
              data={trades}
              title="Recent Trades"
            />
          ) : (
            <Box paddingLeft={1} paddingBottom={1}>
              <Text dimColor>No trades found.</Text>
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

// --- trades subcommand ---

function formatTradeJson(node: TradeSwapNode) {
  return {
    type: node.activityType ?? null,
    sender: node.senderAddress,
    senderHandle: node.senderProfile?.handle ?? null,
    coinAmount: node.coinAmount,
    valueUsd: node.currencyAmountWithPrice.priceUsdc ?? null,
    timestamp: node.blockTimestamp,
    transactionHash: node.transactionHash,
  };
}

async function fetchTradesPage(
  address: string,
  count: number,
  after?: string,
): Promise<PageResult<TradeSwapNode>> {
  const response = await getCoinSwaps({ address, first: count, after });

  if (response.error) {
    throw new Error(extractErrorMessage(response.error));
  }

  const swapActivities = response.data?.zora20Token?.swapActivities;
  const edges = swapActivities?.edges ?? [];
  const items: TradeSwapNode[] = edges.map(
    (e: { node: TradeSwapNode; cursor: string }) => e.node,
  );
  const count_ = swapActivities?.count ?? items.length;
  const pageInfo = swapActivities?.pageInfo as PageInfo | undefined;

  return { items, count: count_, pageInfo };
}

getCommand
  .command("trades")
  .description("Show recent buy/sell activity on a coin")
  .argument("[typeOrId]", "Type prefix (creator-coin, trend) or identifier")
  .argument(
    "[identifier]",
    "Coin address (0x...) or name (when type prefix is given)",
  )
  .option("--limit <n>", "Number of results (default 10, max 20)", "10")
  .option("--after <cursor>", "Pagination cursor from a previous result")
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

    const limit = Math.min(
      20,
      Math.max(1, parseInt(this.opts().limit, 10) || 10),
    );
    const after: string | undefined = this.opts().after;

    if (output === "live" && after) {
      outputErrorAndExit(
        false,
        "--after cannot be used in live mode.",
        "Use --static or --json to paginate with a cursor.",
      );
    }

    const { coin } = await resolveAndValidateCoin(
      json,
      typeOrId,
      identifier,
      "get trades",
    );

    if (json) {
      const result = await fetchTradesPage(coin.address, limit, after).catch(
        (err) =>
          outputErrorAndExit(
            json,
            `Request failed: ${err instanceof Error ? err.message : String(err)}`,
          ),
      );

      outputData(json, {
        json: {
          coin: { name: coin.name, address: coin.address },
          trades: result.items.map(formatTradeJson),
          pageInfo: result.pageInfo ?? null,
        },
        render: () => {},
      });

      track("cli_get_trades", {
        result_count: result.items.length,
        output_format: "json",
      });
    } else {
      const { live, intervalSeconds } = getLiveConfig(this, output);

      if (live) {
        const fetchPage = (cursor?: string) =>
          fetchTradesPage(coin.address, limit, cursor);

        await renderLive(
          <CoinTradesView
            fetchPage={fetchPage}
            coinName={coin.name}
            limit={limit}
            autoRefresh={live}
            intervalSeconds={intervalSeconds}
          />,
        );

        track("cli_get_trades", {
          output_format: "live",
          live,
          interval: intervalSeconds,
        });
      } else {
        const result = await fetchTradesPage(coin.address, limit, after).catch(
          (err) =>
            outputErrorAndExit(
              json,
              `Request failed: ${err instanceof Error ? err.message : String(err)}`,
            ),
        );

        const rankedTrades = result.items.map((t, i) => ({
          ...t,
          rank: i + 1,
        }));

        if (rankedTrades.length === 0) {
          renderOnce(
            <Box
              flexDirection="column"
              paddingLeft={1}
              paddingTop={1}
              paddingBottom={1}
            >
              <Text>
                No trades found for {coin.name} ({truncateAddress(coin.address)}
                )
              </Text>
            </Box>,
          );
        } else {
          const footer =
            result.pageInfo?.hasNextPage && result.pageInfo.endCursor
              ? `Next page: zora get trades ${typeOrId}${identifier ? " " + identifier : ""} --limit ${limit} --after ${result.pageInfo.endCursor}`
              : undefined;
          renderOnce(
            <Table
              columns={coinTradeColumns}
              data={rankedTrades}
              title={`Recent trades \u00b7 ${coin.name}`}
              subtitle={`${rankedTrades.length} of ${result.count}`}
              footer={footer}
            />,
          );
        }

        track("cli_get_trades", {
          result_count: result.items.length,
          output_format: "static",
        });
      }
    }
  });

// --- holders subcommand ---

getCommand
  .command("holders")
  .description("Show top holders of a coin")
  .argument("[typeOrId]", "Type prefix (creator-coin, trend) or identifier")
  .argument(
    "[identifier]",
    "Coin address (0x...) or name (when type prefix is given)",
  )
  .option("--limit <n>", "Number of results per page (max 20)", "10")
  .option("--after <cursor>", "Pagination cursor from a previous result")
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
    const opts = this.opts();
    const limit = parseInt(opts.limit, 10);
    const after: string | undefined = opts.after;

    if (isNaN(limit) || limit <= 0 || limit > 20) {
      outputErrorAndExit(
        json,
        `Invalid --limit value: ${opts.limit}. Must be an integer between 1 and 20.`,
        "Usage: zora get holders --limit 10",
      );
    }

    if (output === "live" && after) {
      outputErrorAndExit(
        false,
        "--after cannot be used in live mode.",
        "Use --static or --json to paginate with a cursor.",
      );
    }

    const { coin, lookupType } = await resolveAndValidateCoin(
      json,
      typeOrId,
      identifier,
      "get holders",
    );

    const totalSupply = Number(coin.totalSupply);

    if (json) {
      let result: PageResult<HolderNode>;
      try {
        result = await fetchHoldersPageForCoin(coin.address, limit, after);
      } catch (err) {
        outputErrorAndExit(
          json,
          `Failed to fetch holders: ${err instanceof Error ? err.message : String(err)}`,
        );
      }

      outputData(json, {
        json: {
          coin: coin.name,
          address: coin.address,
          coinType: coin.coinType,
          totalHolders: result.count ?? 0,
          holders: result.items.map((h, i) => ({
            rank: i + 1,
            handle: h.ownerProfile?.handle ?? h.ownerAddress,
            address: h.ownerAddress,
            balance: formatBalance(h.balance),
            balanceRaw: h.balance,
            ownershipPercent:
              totalSupply > 0
                ? (parseRawBalance(h.balance) / totalSupply) * 100
                : 0,
          })),
          ...(result.pageInfo?.hasNextPage && result.pageInfo.endCursor
            ? { nextCursor: result.pageInfo.endCursor }
            : {}),
        },
        render: () => {},
      });

      track("cli_get_holders", {
        lookup_type: lookupType,
        coin_type: coin.coinType,
        limit,
        total_holders: result.count ?? 0,
        output_format: "json",
      });
    } else {
      const { live, intervalSeconds } = getLiveConfig(this, output);

      if (live) {
        const fetchPage = (cursor?: string) =>
          fetchHoldersPageForCoin(coin.address, limit, cursor);

        await renderLive(
          <CoinHoldersView
            fetchPage={fetchPage}
            coinName={coin.name}
            totalSupplyNum={totalSupply}
            limit={limit}
            autoRefresh={live}
            intervalSeconds={intervalSeconds}
          />,
        );

        track("cli_get_holders", {
          lookup_type: lookupType,
          coin_type: coin.coinType,
          limit,
          output_format: "live",
          interval: intervalSeconds,
        });
      } else {
        let result: PageResult<HolderNode>;
        try {
          result = await fetchHoldersPageForCoin(coin.address, limit, after);
        } catch (err) {
          outputErrorAndExit(
            json,
            `Failed to fetch holders: ${err instanceof Error ? err.message : String(err)}`,
          );
        }

        if (result.items.length === 0) {
          renderOnce(
            <Box
              flexDirection="column"
              paddingLeft={1}
              paddingTop={1}
              paddingBottom={1}
            >
              <Text>No holders found for {coin.name}.</Text>
            </Box>,
          );
        } else {
          const holderColumns = makeHolderColumns({
            totalSupplyNum: totalSupply,
          });
          const rankedItems = result.items.map((item, i) => ({
            ...item,
            rank: i + 1,
          }));

          const footer =
            result.pageInfo?.hasNextPage && result.pageInfo.endCursor
              ? `Next page: zora get holders ${coin.address} --limit ${limit} --after ${result.pageInfo.endCursor}`
              : undefined;

          renderOnce(
            <Table
              columns={holderColumns}
              data={rankedItems}
              title={`Top holders · ${coin.name}`}
              subtitle={`${rankedItems.length} of ${result.count ?? rankedItems.length}`}
              footer={footer}
            />,
          );
        }

        track("cli_get_holders", {
          lookup_type: lookupType,
          coin_type: coin.coinType,
          limit,
          total_holders: result.count ?? 0,
          output_format: "static",
        });
      }
    }
  });
