import { Command } from "commander";
import { Box, Text } from "ink";
import {
  getProfileCoins,
  getProfileBalances,
  setApiKey,
} from "@zoralabs/coins-sdk";
import { getApiKey, getPrivateKey } from "../lib/config.js";
import { normalizeKey } from "../lib/wallet.js";
import { privateKeyToAccount } from "viem/accounts";
import {
  getOutputMode,
  getLiveConfig,
  outputData,
  outputErrorAndExit,
} from "../lib/output.js";
import { renderOnce, renderLive } from "../lib/render.js";
import { Table } from "../components/table.js";
import { ProfileView, type ProfileData } from "../components/ProfileView.js";
import {
  ProfilePostsView,
  postColumns,
  type PostNode,
} from "../components/ProfilePostsView.js";
import { ProfileHoldingsView } from "../components/ProfileHoldingsView.js";
import type { PageResult } from "../components/PaginatedTableView.js";
import { balanceColumns, type BalanceNode } from "../lib/balance-columns.js";
import {
  parseRawBalance,
  normalizeTokenAmount,
} from "../lib/balance-format.js";
import { COIN_TYPE_DISPLAY, type PageInfo } from "../lib/types.js";
import { track } from "../lib/analytics.js";

const extractErrorMessage = (error: unknown): string => {
  if (typeof error === "object" && error !== null && "error" in error) {
    return String((error as Record<string, unknown>).error);
  }
  return JSON.stringify(error);
};

const resolveApiKey = () => {
  const apiKey = getApiKey();
  if (apiKey) {
    setApiKey(apiKey);
  }
};

type PostJson = {
  rank: number;
  name: string;
  symbol: string;
  coinType: string;
  address: string;
  marketCap: string | null;
  marketCapDelta24h: string | null;
  volume24h: string | null;
  createdAt: string | null;
};

type HoldingJson = {
  rank: number;
  name: string | null;
  symbol: string | null;
  coinType: string | null;
  address: string | null;
  balance: string;
  usdValue: number | null;
  priceUsd: number | null;
  marketCap: number | null;
};

const formatPostJson = (post: PostNode, rank: number): PostJson => ({
  rank,
  name: post.name,
  symbol: post.symbol,
  coinType: COIN_TYPE_DISPLAY[post.coinType] ?? post.coinType,
  address: post.address,
  marketCap: post.marketCap ?? null,
  marketCapDelta24h: post.marketCapDelta24h ?? null,
  volume24h: post.volume24h ?? null,
  createdAt: post.createdAt ?? null,
});

const formatHoldingJson = (
  balance: BalanceNode & { rank: number },
): HoldingJson => {
  const priceUsd = balance.coin?.tokenPrice?.priceInUsdc
    ? Number(balance.coin.tokenPrice.priceInUsdc)
    : null;
  const usdValue =
    priceUsd !== null
      ? Number((parseRawBalance(balance.balance) * priceUsd).toFixed(6))
      : null;

  return {
    rank: balance.rank,
    name: balance.coin?.name ?? null,
    symbol: balance.coin?.symbol ?? null,
    coinType: balance.coin?.coinType ?? null,
    address: balance.coin?.address ?? null,
    balance: normalizeTokenAmount(balance.balance),
    usdValue,
    priceUsd,
    marketCap: balance.coin?.marketCap ? Number(balance.coin.marketCap) : null,
  };
};

const fetchProfileData = async (identifier: string): Promise<ProfileData> => {
  const [postsResult, holdingsResult] = await Promise.allSettled([
    getProfileCoins({ identifier, count: 20 }),
    getProfileBalances({ identifier, count: 20, sortOption: "USD_VALUE" }),
  ]);

  if (postsResult.status === "rejected") {
    throw new Error(
      postsResult.reason instanceof Error
        ? postsResult.reason.message
        : String(postsResult.reason),
    );
  }

  if (holdingsResult.status === "rejected") {
    throw new Error(
      holdingsResult.reason instanceof Error
        ? holdingsResult.reason.message
        : String(holdingsResult.reason),
    );
  }

  if (postsResult.value.error) {
    throw new Error(
      `API error (posts): ${extractErrorMessage(postsResult.value.error)}`,
    );
  }

  if (holdingsResult.value.error) {
    throw new Error(
      `API error (holdings): ${extractErrorMessage(holdingsResult.value.error)}`,
    );
  }

  const postEdges = postsResult.value.data?.profile?.createdCoins?.edges ?? [];
  const posts: PostNode[] = postEdges.map((e: { node: PostNode }) => e.node);
  const postsCount =
    postsResult.value.data?.profile?.createdCoins?.count ?? posts.length;

  const holdingEdges =
    holdingsResult.value.data?.profile?.coinBalances?.edges ?? [];
  const holdings: (BalanceNode & { rank: number })[] = holdingEdges.map(
    (e: { node: BalanceNode }, i: number) => ({
      ...e.node,
      rank: i + 1,
    }),
  );
  const holdingsCount =
    holdingsResult.value.data?.profile?.coinBalances?.count ?? holdings.length;

  return { posts, postsCount, holdings, holdingsCount };
};

const resolveIdentifier = (
  identifierArg: string | undefined,
  json: boolean,
): string => {
  if (identifierArg) return identifierArg;

  const envKey = process.env.ZORA_PRIVATE_KEY;
  const key = envKey || getPrivateKey();
  if (!key) {
    return outputErrorAndExit(
      json,
      "No identifier provided and no wallet configured.",
      "Pass an address or handle, or run 'zora setup' first.",
    );
  }
  try {
    return privateKeyToAccount(normalizeKey(key)).address;
  } catch {
    return outputErrorAndExit(
      json,
      "Invalid wallet key. Run 'zora setup --force' to replace it.",
    );
  }
};

export const profileCommand = new Command("profile")
  .description("View profile activity (posts and holdings)")
  .argument(
    "[identifier]",
    "Wallet address or profile handle (defaults to your wallet)",
  )
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .action(async function (this: Command, identifierArg?: string) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    resolveApiKey();
    const { live, intervalSeconds } = getLiveConfig(this, output);

    const identifier = resolveIdentifier(identifierArg, json);

    if (json) {
      const data = await fetchProfileData(identifier).catch((err) =>
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );

      outputData(json, {
        json: {
          posts: data.posts.map((p, i) => formatPostJson(p, i + 1)),
          holdings: data.holdings.map(formatHoldingJson),
        },
        render: () => {},
      });

      track("cli_profile", {
        identifier,
        output_format: "json",
        posts_count: data.postsCount,
        holdings_count: data.holdingsCount,
      });
    } else if (live) {
      const fetchData = () => fetchProfileData(identifier);

      await renderLive(
        <ProfileView
          fetchData={fetchData}
          identifier={identifier}
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
        />,
      );

      track("cli_profile", {
        identifier,
        output_format: "live",
        live,
        interval: intervalSeconds,
      });
    } else {
      const data = await fetchProfileData(identifier).catch((err) =>
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );

      const rankedPosts = data.posts.map((p, i) => ({ ...p, rank: i + 1 }));

      renderOnce(
        <Box flexDirection="column">
          {rankedPosts.length === 0 ? (
            <Box
              flexDirection="column"
              paddingLeft={1}
              paddingTop={1}
              paddingBottom={1}
            >
              <Box>
                <Text>No posts found for this profile.</Text>
              </Box>
            </Box>
          ) : (
            <Table
              columns={postColumns}
              data={rankedPosts}
              title="Posts"
              subtitle={`${rankedPosts.length} of ${data.postsCount}`}
            />
          )}
          {data.holdings.length === 0 ? (
            <Box
              flexDirection="column"
              paddingLeft={1}
              paddingTop={1}
              paddingBottom={1}
            >
              <Box>
                <Text>No holdings found for this profile.</Text>
              </Box>
            </Box>
          ) : (
            <Table
              columns={balanceColumns}
              data={data.holdings}
              title="Holdings"
              subtitle={`${data.holdings.length} of ${data.holdingsCount}`}
            />
          )}
        </Box>,
      );

      track("cli_profile", {
        identifier,
        output_format: "static",
        posts_count: data.postsCount,
        holdings_count: data.holdingsCount,
      });
    }
  });

// --- Subcommands ---

async function fetchPostsPage(
  identifier: string,
  count: number,
  after?: string,
): Promise<PageResult<PostNode>> {
  const response = await getProfileCoins({ identifier, count, after });

  if (response.error) {
    throw new Error(`API error: ${extractErrorMessage(response.error)}`);
  }

  const edges = response.data?.profile?.createdCoins?.edges ?? [];
  const items: PostNode[] = edges.map((e: { node: PostNode }) => e.node);
  const total = response.data?.profile?.createdCoins?.count ?? items.length;
  const pageInfo = response.data?.profile?.createdCoins?.pageInfo as
    | PageInfo
    | undefined;

  return { items, count: total, pageInfo };
}

async function fetchHoldingsPage(
  identifier: string,
  count: number,
  sortOption: BalanceSortOption,
  after?: string,
): Promise<PageResult<BalanceNode>> {
  const response = await getProfileBalances({
    identifier,
    count,
    sortOption,
    after,
  });

  if (response.error) {
    throw new Error(`API error: ${extractErrorMessage(response.error)}`);
  }

  const edges = response.data?.profile?.coinBalances?.edges ?? [];
  const items: BalanceNode[] = edges.map((e: { node: BalanceNode }) => e.node);
  const total = response.data?.profile?.coinBalances?.count ?? items.length;
  const pageInfo = response.data?.profile?.coinBalances?.pageInfo as
    | PageInfo
    | undefined;

  return { items, count: total, pageInfo };
}

profileCommand
  .command("posts")
  .description("View profile posts (created coins) with pagination")
  .argument(
    "[identifier]",
    "Wallet address or profile handle (defaults to your wallet)",
  )
  .option("--limit <n>", "Number of results per page (max 20)", "10")
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .option("--after <cursor>", "Pagination cursor from a previous result")
  .action(async function (this: Command, identifierArg?: string) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    resolveApiKey();
    const opts = this.opts();
    const after: string | undefined = opts.after;
    const limit = Math.min(20, Math.max(1, parseInt(opts.limit, 10) || 10));
    const { live, intervalSeconds } = getLiveConfig(this, output);
    const identifier = resolveIdentifier(identifierArg, json);

    if (json) {
      const result = await fetchPostsPage(identifier, limit, after).catch(
        (err) =>
          outputErrorAndExit(
            json,
            `Request failed: ${err instanceof Error ? err.message : String(err)}`,
          ),
      );
      outputData(json, {
        json: {
          posts: result.items.map((p, i) => formatPostJson(p, i + 1)),
          pageInfo: result.pageInfo ?? null,
        },
        render: () => {},
      });

      track("cli_profile_posts", {
        identifier,
        output_format: "json",
        count: result.count,
      });
    } else if (live) {
      const fetchPage = (cursor?: string) =>
        fetchPostsPage(identifier, limit, cursor);

      await renderLive(
        <ProfilePostsView
          fetchPage={fetchPage}
          identifier={identifier}
          limit={limit}
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
        />,
      );

      track("cli_profile_posts", {
        identifier,
        output_format: "live",
        live,
        interval: intervalSeconds,
      });
    } else {
      const result = await fetchPostsPage(identifier, limit, after).catch(
        (err) =>
          outputErrorAndExit(
            json,
            `Request failed: ${err instanceof Error ? err.message : String(err)}`,
          ),
      );
      const rankedPosts = result.items.map((p, i) => ({
        ...p,
        rank: i + 1,
      }));

      if (rankedPosts.length === 0) {
        renderOnce(
          <Box
            flexDirection="column"
            paddingLeft={1}
            paddingTop={1}
            paddingBottom={1}
          >
            <Text>No posts found for this profile.</Text>
          </Box>,
        );
      } else {
        const footer =
          result.pageInfo?.hasNextPage && result.pageInfo.endCursor
            ? `Next page: zora profile posts ${identifier} --limit ${limit} --after ${result.pageInfo.endCursor}`
            : undefined;
        renderOnce(
          <Table
            columns={postColumns}
            data={rankedPosts}
            title="Posts"
            subtitle={`${rankedPosts.length} of ${result.count}`}
            footer={footer}
          />,
        );
      }

      track("cli_profile_posts", {
        identifier,
        output_format: "static",
        count: result.count,
      });
    }
  });

type BalanceSortOption =
  | "BALANCE"
  | "MARKET_CAP"
  | "USD_VALUE"
  | "PRICE_CHANGE"
  | "MARKET_VALUE_USD";

const SORT_MAP: Record<string, BalanceSortOption> = {
  "usd-value": "USD_VALUE",
  balance: "BALANCE",
  "market-cap": "MARKET_CAP",
  "price-change": "PRICE_CHANGE",
};
const SORT_OPTIONS = Object.keys(SORT_MAP).join(", ");

profileCommand
  .command("holdings")
  .description("View profile holdings (coin balances) with pagination")
  .argument(
    "[identifier]",
    "Wallet address or profile handle (defaults to your wallet)",
  )
  .option("--sort <sort>", `Sort by: ${SORT_OPTIONS}`, "usd-value")
  .option("--limit <n>", "Number of results per page (max 20)", "10")
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .option("--after <cursor>", "Pagination cursor from a previous result")
  .action(async function (this: Command, identifierArg?: string) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    resolveApiKey();
    const opts = this.opts();
    const after: string | undefined = opts.after;
    const sort = opts.sort as string;
    const sortOption = SORT_MAP[sort];
    if (!sortOption) {
      outputErrorAndExit(
        json,
        `Invalid --sort value: ${sort}.`,
        `Supported: ${SORT_OPTIONS}`,
      );
    }
    const limit = Math.min(20, Math.max(1, parseInt(opts.limit, 10) || 10));
    const { live, intervalSeconds } = getLiveConfig(this, output);
    const identifier = resolveIdentifier(identifierArg, json);

    if (json) {
      const result = await fetchHoldingsPage(
        identifier,
        limit,
        sortOption,
        after,
      ).catch((err) =>
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );
      const rankedHoldings = result.items.map((h, i) => ({
        ...h,
        rank: i + 1,
      }));
      outputData(json, {
        json: {
          holdings: rankedHoldings.map(formatHoldingJson),
          pageInfo: result.pageInfo ?? null,
        },
        render: () => {},
      });

      track("cli_profile_holdings", {
        identifier,
        output_format: "json",
        sort,
        count: result.count,
      });
    } else if (live) {
      const fetchPage = (cursor?: string) =>
        fetchHoldingsPage(identifier, limit, sortOption, cursor);

      await renderLive(
        <ProfileHoldingsView
          fetchPage={fetchPage}
          identifier={identifier}
          limit={limit}
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
        />,
      );

      track("cli_profile_holdings", {
        identifier,
        output_format: "live",
        live,
        sort,
        interval: intervalSeconds,
      });
    } else {
      const result = await fetchHoldingsPage(
        identifier,
        limit,
        sortOption,
        after,
      ).catch((err) =>
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );
      const rankedHoldings = result.items.map((h, i) => ({
        ...h,
        rank: i + 1,
      }));

      if (rankedHoldings.length === 0) {
        renderOnce(
          <Box
            flexDirection="column"
            paddingLeft={1}
            paddingTop={1}
            paddingBottom={1}
          >
            <Text>No holdings found for this profile.</Text>
            <Box marginTop={1} flexDirection="column">
              <Text dimColor>Buy coins to see them here:</Text>
              <Text dimColor> zora buy {"<address>"} --eth 0.001</Text>
            </Box>
          </Box>,
        );
      } else {
        const footer =
          result.pageInfo?.hasNextPage && result.pageInfo.endCursor
            ? `Next page: zora profile holdings ${identifier} --sort ${sort} --limit ${limit} --after ${result.pageInfo.endCursor}`
            : undefined;
        renderOnce(
          <Table
            columns={balanceColumns}
            data={rankedHoldings}
            title={`Holdings · sorted by ${sort}`}
            subtitle={`${rankedHoldings.length} of ${result.count}`}
            footer={footer}
          />,
        );
      }

      track("cli_profile_holdings", {
        identifier,
        output_format: "static",
        sort,
        count: result.count,
      });
    }
  });
