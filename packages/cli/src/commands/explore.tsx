import { Command } from "commander";
import {
  setApiKey,
  getCoinsTopVolume24h,
  getCoinsMostValuable,
  getCoinsNew,
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
import {
  getOutputMode,
  getLiveConfig,
  outputErrorAndExit,
  outputJson,
} from "../lib/output.js";
import { track } from "../lib/analytics.js";
import { computeMarketCapChange24h } from "../lib/format.js";
import { apiErrorMessage } from "../lib/errors.js";
import {
  SORT_LABELS,
  TYPE_LABELS,
  COIN_TYPE_DISPLAY,
  type SortOption,
  type TypeOption,
  type CoinNode,
} from "../lib/types.js";
import { formatCompactUsd, formatMcapChange } from "../lib/format.js";
import { renderLive, renderOnce } from "../lib/render.js";
import { Table, type Column } from "../components/table.js";
import {
  ExploreView,
  type ExplorePageResult,
} from "../components/ExploreView.js";

type SdkQueryFn = (opts: { count: number; after?: string }) => Promise<any>;

type SocialAccount = {
  username?: string;
  displayName?: string;
  followerCount?: number;
  id?: string;
};

type RawExploreNode = {
  name?: string;
  description?: string;
  address?: string;
  symbol?: string;
  coinType?: string;
  chainId?: number;
  platformBlocked?: boolean;
  totalSupply?: string;
  marketCap?: string;
  marketCapDelta24h?: string;
  volume24h?: string;
  totalVolume?: string;
  uniqueHolders?: number;
  createdAt?: string;
  creatorAddress?: string;
  creatorProfile?: {
    handle?: string;
    socialAccounts?: {
      instagram?: SocialAccount;
      tiktok?: SocialAccount;
      twitter?: SocialAccount;
      farcaster?: SocialAccount;
    };
  };
  mediaContent?: {
    mimeType?: string;
    originalUri?: string;
    previewImage?: { medium?: string };
  };
  tokenPrice?: { priceInUsdc?: string };
};

type FormattedSocialAccounts = {
  instagram: SocialAccount | null;
  tiktok: SocialAccount | null;
  twitter: SocialAccount | null;
  farcaster: SocialAccount | null;
};

type FormattedExploreCoinJson = {
  name: string | null;
  description: string | null;
  symbol: string | null;
  coinType: string | null;
  chainId: number | null;
  address: string | null;
  platformBlocked: boolean;
  totalSupply: string | null;
  creatorAddress: string | null;
  creatorHandle: string | null;
  socialAccounts: FormattedSocialAccounts | null;
  mediaContentMimeType: string | null;
  mediaContentOriginalUri: string | null;
  previewImage: string | null;
  priceUsd: number | null;
  marketCap: number | null;
  marketCapDelta24h: number | null;
  marketCapChange24h: number | null;
  volume24h: number | null;
  totalVolume: number | null;
  uniqueHolders: number | null;
  createdAt: string | null;
};

const formatExploreCoinJson = (
  node: RawExploreNode,
): FormattedExploreCoinJson => {
  const marketCap = node.marketCap ? Number(node.marketCap) : null;
  const marketCapDelta24h = node.marketCapDelta24h
    ? Number(node.marketCapDelta24h)
    : null;
  const marketCapChange24h = computeMarketCapChange24h(
    marketCap,
    marketCapDelta24h,
  );
  const priceUsd = node.tokenPrice?.priceInUsdc
    ? Number(node.tokenPrice.priceInUsdc)
    : null;
  const coinType = node.coinType
    ? (COIN_TYPE_DISPLAY[node.coinType] ?? node.coinType)
    : null;

  const socials = node.creatorProfile?.socialAccounts;
  const socialAccounts: FormattedSocialAccounts | null = socials
    ? {
        instagram: socials.instagram ?? null,
        tiktok: socials.tiktok ?? null,
        twitter: socials.twitter ?? null,
        farcaster: socials.farcaster ?? null,
      }
    : null;

  return {
    name: node.name ?? null,
    description: node.description ?? null,
    symbol: node.symbol ?? null,
    coinType,
    chainId: node.chainId ?? null,
    address: node.address ?? null,
    platformBlocked: node.platformBlocked ?? false,
    totalSupply: node.totalSupply ?? null,
    creatorAddress: node.creatorAddress ?? null,
    creatorHandle: node.creatorProfile?.handle ?? null,
    socialAccounts,
    mediaContentMimeType: node.mediaContent?.mimeType ?? null,
    mediaContentOriginalUri: node.mediaContent?.originalUri ?? null,
    previewImage: node.mediaContent?.previewImage?.medium ?? null,
    priceUsd,
    marketCap,
    marketCapDelta24h,
    marketCapChange24h,
    volume24h: node.volume24h ? Number(node.volume24h) : null,
    totalVolume: node.totalVolume ? Number(node.totalVolume) : null,
    uniqueHolders: node.uniqueHolders ?? null,
    createdAt: node.createdAt ?? null,
  };
};

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

const STATIC_COLUMNS: Column<CoinNode & { rank: number }>[] = [
  { header: "#", width: 4, accessor: (c) => String(c.rank) },
  { header: "Name", width: 20, accessor: (c) => c.name ?? "Unknown" },
  { header: "Address", width: 48, accessor: (c) => c.address ?? "" },
  {
    header: "Type",
    width: 14,
    accessor: (c) => COIN_TYPE_DISPLAY[c.coinType ?? ""] ?? c.coinType ?? "",
  },
  {
    header: "Market Cap",
    width: 12,
    accessor: (c) => formatCompactUsd(c.marketCap),
  },
  {
    header: "24h Vol",
    width: 12,
    accessor: (c) => formatCompactUsd(c.volume24h),
  },
  {
    header: "24h Change",
    width: 11,
    accessor: (c) => formatMcapChange(c.marketCap, c.marketCapDelta24h).text,
    color: (c) => formatMcapChange(c.marketCap, c.marketCapDelta24h).color,
  },
];

const SORT_OPTIONS = Object.keys(SORT_LABELS).join(", ");

export const exploreCommand = new Command("explore")
  .description("Browse top, new, and highest volume coins")
  .option("--sort <sort>", `Sort by: ${SORT_OPTIONS}`, "mcap")
  .option(
    "--type <type>",
    "Filter by type: all, trend, creator-coin, post (availability varies by sort)",
    "creator-coin",
  )
  .option("--limit <n>", "Number of results (max 20)", "10")
  .option("--after <cursor>", "Pagination cursor from a previous result")
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .action(async function (this: Command, opts) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
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

    if (json) {
      let response: Awaited<ReturnType<SdkQueryFn>>;
      try {
        response = await queryFn({ count: limit, after });
      } catch (err) {
        outputErrorAndExit(json, `Request failed: ${apiErrorMessage(err)}`);
      }

      if (response.error) {
        const msg =
          typeof response.error === "object" && response.error.error
            ? response.error.error
            : JSON.stringify(response.error);
        outputErrorAndExit(json, `API error: ${msg}`);
      }

      const edges = response.data?.exploreList?.edges ?? [];
      const rawNodes: RawExploreNode[] = edges.map((e: any) => e.node);
      const coins = rawNodes.map((node, i) => formatExploreCoinJson(node));
      const pageInfo = response.data?.exploreList?.pageInfo as
        | { endCursor?: string; hasNextPage: boolean }
        | undefined;

      outputJson({ coins, pageInfo: pageInfo ?? null });

      track("cli_explore", {
        sort,
        type,
        limit,
        paginated: after !== undefined,
        result_count: coins.length,
        has_next_page: pageInfo?.hasNextPage ?? false,
        output_format: "json",
      });
    } else {
      const { live, intervalSeconds } = getLiveConfig(this, output);

      const fetchPage = async (cursor?: string): Promise<ExplorePageResult> => {
        const response = await queryFn({ count: limit, after: cursor });
        if (response.error) {
          const msg =
            typeof response.error === "object" && response.error.error
              ? response.error.error
              : JSON.stringify(response.error);
          throw new Error(msg);
        }
        const edges = response.data?.exploreList?.edges ?? [];
        const coins: CoinNode[] = edges.map((e: any) => e.node);
        const pageInfo = response.data?.exploreList?.pageInfo;
        return { coins, pageInfo };
      };

      if (live) {
        await renderLive(
          <ExploreView
            fetchPage={fetchPage}
            sort={sort}
            type={type}
            limit={limit}
            initialCursor={after}
            autoRefresh={live}
            intervalSeconds={intervalSeconds}
          />,
        );

        track("cli_explore", {
          sort,
          type,
          limit,
          live,
          interval: intervalSeconds,
          paginated: after !== undefined,
          output_format: "live",
        });
      } else {
        const { coins } = await fetchPage(after).catch((err) =>
          outputErrorAndExit(
            false,
            `Request failed: ${err instanceof Error ? err.message : String(err)}`,
          ),
        );

        const title =
          type !== "all"
            ? `${SORT_LABELS[sort]} \u00b7 ${TYPE_LABELS[type]}`
            : SORT_LABELS[sort];
        const rankedCoins = coins.map((c, i) => ({
          ...c,
          rank: i + 1,
        }));

        renderOnce(
          <Table columns={STATIC_COLUMNS} data={rankedCoins} title={title} />,
        );

        track("cli_explore", {
          sort,
          type,
          limit,
          live: false,
          paginated: after !== undefined,
          result_count: coins.length,
          output_format: "static",
        });
      }
    }
  });
