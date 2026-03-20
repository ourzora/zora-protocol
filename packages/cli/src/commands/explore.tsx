import { Command } from "commander";
import {
  setApiKey,
  getCoinsTopVolume24h,
  getCoinsMostValuable,
  getCoinsNew,
  getCoinsTopGainers,
  getCoinsLastTraded,
  getCoinsLastTradedUnique,
  getExploreTopVolumeAll24h,
  getExploreTopVolumeCreators24h,
  getExploreNewAll,
  getExploreFeaturedCreators,
  getExploreFeaturedVideos,
  getCreatorCoins,
  getMostValuableCreatorCoins,
  getMostValuableAll,
  getMostValuableTrends,
  getNewTrends,
  getTopVolumeTrends24h,
  getTrendingAll,
  getTrendingCreators,
  getTrendingPosts,
  getTrendingTrends,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { getJson, outputErrorAndExit, outputData } from "../lib/output.js";
import { styledText } from "../lib/format.js";
import { track } from "../lib/analytics.js";
import {
  SORT_LABELS,
  TYPE_LABELS,
  COIN_TYPE_DISPLAY,
  type SortOption,
  type TypeOption,
  type CoinNode,
} from "../lib/types.js";
import { Box, Text } from "ink";
import { renderOnce } from "../lib/render.js";
import { TableComponent } from "../components/table.js";
import type { Column } from "../components/table.js";

type SdkQueryFn = (opts: { count: number; after?: string }) => Promise<any>;

export const QUERY_MAP: Record<
  SortOption,
  Partial<Record<TypeOption, SdkQueryFn>>
> = {
  mcap: {
    all: getMostValuableAll,
    trend: getMostValuableTrends,
    "creator-coin": getMostValuableCreatorCoins,
    post: getCoinsMostValuable,
  },
  volume: {
    all: getExploreTopVolumeAll24h,
    trend: getTopVolumeTrends24h,
    "creator-coin": getExploreTopVolumeCreators24h,
    post: getCoinsTopVolume24h,
  },
  new: {
    all: getExploreNewAll,
    trend: getNewTrends,
    "creator-coin": getCreatorCoins,
    post: getCoinsNew,
  },
  gainers: {
    post: getCoinsTopGainers,
  },
  "last-traded": {
    post: getCoinsLastTraded,
  },
  "last-traded-unique": {
    post: getCoinsLastTradedUnique,
  },
  trending: {
    all: getTrendingAll,
    trend: getTrendingTrends,
    "creator-coin": getTrendingCreators,
    post: getTrendingPosts,
  },
  featured: {
    "creator-coin": getExploreFeaturedCreators,
    post: getExploreFeaturedVideos,
  },
};

export const formatCompactCurrency = (value: string | undefined): string => {
  if (!value) return "$0";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(Number(value));
};

export const formatChange = (
  marketCap: string | undefined,
  delta: string | undefined,
): string => {
  if (!delta || !marketCap) return "-";
  const cap = Number(marketCap);
  const d = Number(delta);
  if (cap === 0) return "-";
  const prevCap = cap - d;
  if (prevCap === 0) return "-";
  const pct = (d / prevCap) * 100;
  const sign = pct >= 0 ? "+" : "";
  return `${sign}${pct.toFixed(1)}%`;
};

const changeColor = (row: CoinNode): string | undefined => {
  if (!row.marketCapDelta24h || !row.marketCap) return undefined;
  const cap = Number(row.marketCap);
  const d = Number(row.marketCapDelta24h);
  if (cap === 0 || cap - d === 0) return undefined;
  const pct = (d / (cap - d)) * 100;
  if (pct > 0) return "green";
  if (pct < 0) return "red";
  return undefined;
};

const SORT_OPTIONS = Object.keys(SORT_LABELS).join(", ");

const rankColumn: Column<CoinNode & { rank: number }> = {
  header: "#",
  width: 5,
  accessor: (r) => String(r.rank),
};

const exploreColumns: Column<CoinNode & { rank: number }>[] = [
  { header: "Name", width: 27, accessor: (r) => r.name ?? "Unknown" },
  { header: "Address", width: 44, accessor: (r) => r.address ?? "" },
  {
    header: "Type",
    width: 16,
    accessor: (r) => COIN_TYPE_DISPLAY[r.coinType ?? ""] ?? r.coinType ?? "",
  },
  {
    header: "Market Cap",
    width: 14,
    accessor: (r) => formatCompactCurrency(r.marketCap),
  },
  {
    header: "24h Vol",
    width: 14,
    accessor: (r) => formatCompactCurrency(r.volume24h),
  },
  {
    header: "24h Change",
    width: 12,
    accessor: (r) => formatChange(r.marketCap, r.marketCapDelta24h),
    color: changeColor,
  },
];

export const exploreCommand = new Command("explore")
  .description("Browse top, new, and highest volume coins")
  .option("--sort <sort>", `Sort by: ${SORT_OPTIONS}`, "mcap")
  .option(
    "--type <type>",
    "Filter by type: all, trend, creator-coin, post (availability varies by sort)",
    "post",
  )
  .option("--limit <n>", "Number of results (max 20)", "10")
  .option("--after <cursor>", "Pagination cursor from a previous result")
  .action(async function (this: Command, opts) {
    const json = getJson(this);
    const sort = opts.sort as SortOption;
    const type = opts.type as TypeOption;
    const limit = parseInt(opts.limit, 10);
    const after: string | undefined = opts.after;

    if (isNaN(limit) || limit <= 0 || limit > 20) {
      outputErrorAndExit(
        json,
        `Invalid --limit value: ${opts.limit}. Must be an integer between 1 and 20.`,
        "Usage: zora explore --limit 10",
      );
    }

    if (!QUERY_MAP[sort]) {
      outputErrorAndExit(
        json,
        `Invalid --sort value: ${sort}.`,
        `Supported: ${SORT_OPTIONS}`,
      );
    }

    if (!QUERY_MAP[sort][type]) {
      const supported = Object.keys(QUERY_MAP[sort]);
      outputErrorAndExit(
        json,
        `Invalid --type for --sort ${sort}.`,
        `Supported: ${supported.join(", ")}`,
      );
    }

    const apiKey = getApiKey();
    if (apiKey) {
      setApiKey(apiKey);
    }

    const queryFn = QUERY_MAP[sort][type]!;
    let response: Awaited<ReturnType<SdkQueryFn>>;
    try {
      response = await queryFn({ count: limit, after });
    } catch (err) {
      outputErrorAndExit(
        json,
        `Request failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    if (response.error) {
      const msg =
        typeof response.error === "object" && response.error.error
          ? response.error.error
          : JSON.stringify(response.error);
      outputErrorAndExit(json, `API error: ${msg}`);
    }

    const edges = response.data?.exploreList?.edges ?? [];
    const coins: CoinNode[] = edges.map((e: any) => e.node);
    const pageInfo = response.data?.exploreList?.pageInfo as
      | { endCursor?: string; hasNextPage: boolean }
      | undefined;

    if (coins.length === 0) {
      outputData(json, {
        json: { coins: [], pageInfo: pageInfo ?? null },
        table: () => {
          renderOnce(
            <Box flexDirection="column" paddingLeft={1} marginTop={1}>
              <Text>No coins found.</Text>
              <Box marginTop={1} flexDirection="column">
                <Text dimColor>
                  Try a different sort or type (defaults to posts):
                </Text>
                <Text dimColor> zora explore --sort volume --type all</Text>
                <Text dimColor> zora explore --sort new --type all</Text>
              </Box>
            </Box>,
          );
        },
      });
      return;
    }

    const rankedCoins = coins.map((c, i) => ({ ...c, rank: i + 1 }));
    const columns = after ? exploreColumns : [rankColumn, ...exploreColumns];
    const title =
      type !== "all"
        ? `${SORT_LABELS[sort]} \u00b7 ${TYPE_LABELS[type]}`
        : SORT_LABELS[sort];
    const subtitle = `${coins.length} result${coins.length !== 1 ? "s" : ""}`;

    outputData(json, {
      json: { coins, pageInfo: pageInfo ?? null },
      table: () => {
        renderOnce(
          <TableComponent
            columns={columns}
            data={rankedCoins}
            title={title}
            subtitle={subtitle}
          />,
        );
        // Use console.log instead of Ink here — Ink wraps text to terminal width,
        // which breaks long cursor strings across lines and prevents copy-paste.
        if (pageInfo?.hasNextPage && pageInfo.endCursor) {
          console.log(
            `\n ${styledText(`Next page: zora explore --sort ${sort} --type ${type} --limit ${limit} --after ${pageInfo.endCursor}`, "dim")}`,
          );
        }
      },
    });

    track("cli_explore", {
      sort,
      type,
      limit,
      paginated: after !== undefined,
      result_count: coins.length,
      has_next_page: pageInfo?.hasNextPage ?? false,
      output_format: json ? "json" : "text",
    });
  });
