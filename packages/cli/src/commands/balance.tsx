import { getProfileBalances, setApiKey } from "@zoralabs/coins-sdk";
import { Command } from "commander";
import { Box, Text } from "ink";
import { BalanceCoinsView } from "../components/BalanceCoinsView.js";
import { BalanceView, type BalanceData } from "../components/BalanceView.js";
import type { PageResult } from "../components/PaginatedTableView.js";
import { Table } from "../components/table.js";
import { track } from "../lib/analytics.js";
import {
  API_KEY_BANNER,
  balanceColumns,
  SORT_LABELS,
  walletColumns,
  type BalanceNode,
  type SortFlag,
} from "../lib/balance-columns.js";
import {
  computeBalanceUsdValue,
  normalizeTokenAmount,
} from "../lib/balance-format.js";
import { getApiKey } from "../lib/config.js";
import { apiErrorMessage, extractErrorMessage } from "../lib/errors.js";
import { computeMarketCapChange24h, formatCoinType } from "../lib/format.js";
import {
  getLiveConfig,
  getOutputMode,
  outputData,
  outputErrorAndExit,
} from "../lib/output.js";
import { renderLive, renderOnce } from "../lib/render.js";
import type { PageInfo } from "../lib/types.js";
import { fetchWalletBalances } from "../lib/wallet-balances.js";
import { resolveAccounts } from "../lib/wallet.js";

export {
  API_KEY_BANNER,
  balanceColumns,
  SORT_LABELS,
  walletColumns,
  type BalanceNode,
  type SortFlag,
};

type FormattedBalanceJson = {
  rank: number;
  name: string | null;
  symbol: string | null;
  type: string | null;
  coinType: string | null;
  chainId: number | null;
  address: string | null;
  creatorHandle: string | null;
  previewImage: string | null;
  balance: string;
  usdValue: number | null;
  priceUsd: number | null;
  marketCap: number | null;
  marketCapDelta24h: number | null;
  marketCapChange24h: number | null;
  volume24h: number | null;
  totalVolume: number | null;
};

const SORT_MAP: Record<
  SortFlag,
  "USD_VALUE" | "BALANCE" | "MARKET_CAP" | "PRICE_CHANGE"
> = {
  "usd-value": "USD_VALUE",
  balance: "BALANCE",
  "market-cap": "MARKET_CAP",
  "price-change": "PRICE_CHANGE",
};

const SORT_OPTIONS = Object.keys(SORT_LABELS).join(", ");

const formatBalanceJson = (
  balance: BalanceNode,
  rank: number,
): FormattedBalanceJson => {
  const priceUsd = balance.coin?.tokenPrice?.priceInUsdc;
  const marketCap = balance.coin?.marketCap
    ? Number(balance.coin.marketCap)
    : null;
  const marketCapDelta24h = balance.coin?.marketCapDelta24h
    ? Number(balance.coin.marketCapDelta24h)
    : null;
  const volume24h = balance.coin?.volume24h
    ? Number(balance.coin.volume24h)
    : null;
  const totalVolume = balance.coin?.totalVolume
    ? Number(balance.coin.totalVolume)
    : null;
  const priceUsdValue = priceUsd ? Number(priceUsd) : null;

  const usdValue = computeBalanceUsdValue(
    balance.balance,
    balance.valuation?.marketValueUsd,
    priceUsd,
  );

  const marketCapChange24h = computeMarketCapChange24h(
    marketCap,
    marketCapDelta24h,
  );

  return {
    rank,
    name: balance.coin?.name ?? null,
    symbol: balance.coin?.symbol ?? null,
    type: formatCoinType(balance.coin?.coinType) || null,
    coinType: balance.coin?.coinType ?? null,
    chainId: balance.coin?.chainId ?? null,
    address: balance.coin?.address ?? null,
    creatorHandle: balance.coin?.creatorProfile?.handle ?? null,
    previewImage: balance.coin?.mediaContent?.previewImage?.medium ?? null,
    balance: normalizeTokenAmount(balance.balance),
    usdValue,
    priceUsd: priceUsdValue,
    marketCap,
    marketCapDelta24h,
    marketCapChange24h,
    volume24h,
    totalVolume,
  };
};

// --- Shared helpers ---

async function resolveContext() {
  const { privateKeyAccount: account, smartWalletAccount } =
    await resolveAccounts();

  const apiKey = getApiKey();
  if (apiKey) {
    setApiKey(apiKey);
  }

  return {
    account,
    smartWalletAccount,
    hasApiKey: !!apiKey,
  };
}

function renderWallet(
  json: boolean,
  walletAddress: string,
  walletResult: Awaited<ReturnType<typeof fetchWalletBalances>>,
) {
  outputData(json, {
    json: { walletAddress, wallet: walletResult.walletBalancesJson },
    render: () => {
      renderOnce(
        <Table
          columns={walletColumns}
          data={walletResult.walletBalances}
          title="Wallet"
        />,
      );
    },
  });
}

function renderCoins(
  json: boolean,
  walletAddress: string,
  balances: BalanceNode[],
  total: number,
  sort: SortFlag,
  limit: number,
  pageInfo?: PageInfo,
  hasApiKey?: boolean,
) {
  const rankedBalances = balances.map((balance, index) => ({
    ...balance,
    rank: index + 1,
  }));

  outputData(json, {
    json: {
      walletAddress,
      coins: rankedBalances.map((balance) =>
        formatBalanceJson(balance, balance.rank),
      ),
      pageInfo: pageInfo ?? null,
    },
    render: () => {
      if (balances.length === 0) {
        console.log("\n No coin balances found.\n");
        console.log(" Buy coins to see them here:");
        console.log("   zora buy <address> --eth 0.001\n");
      } else {
        const footer =
          pageInfo?.hasNextPage && pageInfo.endCursor
            ? `Next page: zora balance coins --sort ${sort} --limit ${limit} --after ${pageInfo.endCursor}`
            : undefined;
        renderOnce(
          <Box flexDirection="column">
            <Table
              columns={balanceColumns}
              data={rankedBalances}
              title={`Coins · sorted by ${SORT_LABELS[sort]}`}
              subtitle={`${balances.length} of ${total}`}
              footer={footer}
            />
            {!hasApiKey && (
              <Box paddingLeft={1}>
                <Text dimColor>{API_KEY_BANNER}</Text>
              </Box>
            )}
          </Box>,
        );
      }
    },
  });
}

async function fetchCoins(
  json: boolean,
  address: string,
  sort: SortFlag,
  limit: number,
  after?: string,
) {
  let response: Awaited<ReturnType<typeof getProfileBalances>>;
  try {
    response = await getProfileBalances({
      identifier: address,
      count: limit,
      sortOption: SORT_MAP[sort],
      after,
    });
  } catch (err) {
    return outputErrorAndExit(json, `Request failed: ${apiErrorMessage(err)}`);
  }

  if (response.error) {
    return outputErrorAndExit(
      json,
      `API error: ${extractErrorMessage(response.error)}`,
    );
  }

  const edges = response.data?.profile?.coinBalances?.edges ?? [];
  const balances: BalanceNode[] = edges.map(
    (e: { node: BalanceNode }) => e.node,
  );
  const total = response.data?.profile?.coinBalances?.count ?? balances.length;
  const pageInfo = response.data?.profile?.coinBalances?.pageInfo as
    | PageInfo
    | undefined;

  return { balances, total, pageInfo };
}

function validateCoinOpts(json: boolean, sort: string, limitStr: string) {
  if (!SORT_MAP[sort as SortFlag]) {
    outputErrorAndExit(
      json,
      `Invalid --sort value: ${sort}.`,
      `Supported: ${SORT_OPTIONS}`,
    );
  }

  const limit = parseInt(limitStr, 10);
  if (isNaN(limit) || limit <= 0 || limit > 20) {
    outputErrorAndExit(
      json,
      `Invalid --limit value: ${limitStr}. Must be an integer between 1 and 20.`,
    );
  }

  return { sort: sort as SortFlag, limit };
}

// --- Commands ---

export const balanceCommand = new Command("balance")
  .description("Show balances in your wallet")
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .action(async function (this: Command) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    const { account, smartWalletAccount, hasApiKey } = await resolveContext();
    const { live, intervalSeconds } = getLiveConfig(this, output);

    const walletAddress = smartWalletAccount?.address ?? account.address;

    const sort: SortFlag = "usd-value";
    const limit = 10;

    const fetchBalanceData = async (): Promise<BalanceData> => {
      const [walletResult, coinsResult] = await Promise.allSettled([
        fetchWalletBalances(walletAddress),
        fetchCoins(json, walletAddress, sort, limit),
      ]);

      if (
        walletResult.status === "rejected" ||
        coinsResult.status === "rejected"
      ) {
        const err =
          walletResult.status === "rejected"
            ? walletResult.reason
            : (coinsResult as PromiseRejectedResult).reason;
        throw err instanceof Error ? err : new Error(String(err));
      }

      const rankedBalances = coinsResult.value.balances.map(
        (balance, index) => ({
          ...balance,
          rank: index + 1,
        }),
      );

      return {
        walletBalances: walletResult.value.walletBalances,
        walletBalancesJson: walletResult.value.walletBalancesJson,
        rankedBalances,
        total: coinsResult.value.total,
      };
    };

    if (json) {
      const data = await fetchBalanceData().catch((err) =>
        outputErrorAndExit(json, `Request failed: ${apiErrorMessage(err)}`),
      );

      outputData(json, {
        json: {
          walletAddress,
          wallet: data.walletBalancesJson,
          coins: data.rankedBalances.map((balance) =>
            formatBalanceJson(balance, balance.rank),
          ),
        },
        render: () => {},
      });

      track("cli_balances", {
        sort,
        limit,
        live: false,
        result_count: data.rankedBalances.length,
        total_count: data.total,
        output_format: "json",
      });
    } else if (live) {
      await renderLive(
        <BalanceView
          fetchData={fetchBalanceData}
          sort={sort}
          mode="full"
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
          hasApiKey={hasApiKey}
        />,
      );

      track("cli_balances", {
        sort,
        limit,
        live,
        interval: intervalSeconds,
        output_format: "live",
      });
    } else {
      const data = await fetchBalanceData().catch((err) =>
        outputErrorAndExit(json, `Request failed: ${apiErrorMessage(err)}`),
      );

      renderOnce(
        <Box flexDirection="column">
          <Table
            columns={walletColumns}
            data={data.walletBalances}
            title="Wallet"
          />
          {data.rankedBalances.length === 0 ? (
            <Box
              flexDirection="column"
              paddingLeft={1}
              paddingTop={1}
              paddingBottom={1}
            >
              <Text>No coin balances found.</Text>
              <Box marginTop={1} flexDirection="column">
                <Text dimColor>Buy coins to see them here:</Text>
                <Text dimColor> zora buy {"<address>"} --eth 0.001</Text>
              </Box>
            </Box>
          ) : (
            <>
              <Table
                columns={balanceColumns}
                data={data.rankedBalances}
                title={`Coins · sorted by ${SORT_LABELS[sort]}`}
                subtitle={`${data.rankedBalances.length} of ${data.total}`}
              />
              {!hasApiKey && (
                <Box paddingLeft={1}>
                  <Text dimColor>{API_KEY_BANNER}</Text>
                </Box>
              )}
            </>
          )}
        </Box>,
      );

      track("cli_balances", {
        sort,
        limit,
        live: false,
        result_count: data.rankedBalances.length,
        total_count: data.total,
        output_format: "static",
      });
    }
  });

balanceCommand
  .command("spendable")
  .description("Show wallet token balances (ETH, USDC, ZORA)")
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .action(async function (this: Command) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    const { account, smartWalletAccount } = await resolveContext();
    const { live, intervalSeconds } = getLiveConfig(this, output);

    const walletAddress = smartWalletAccount?.address ?? account.address;

    const fetchSpendableData = async (): Promise<BalanceData> => {
      const walletResult = await fetchWalletBalances(walletAddress);
      return {
        walletBalances: walletResult.walletBalances,
        walletBalancesJson: walletResult.walletBalancesJson,
        rankedBalances: [],
        total: 0,
      };
    };

    if (json) {
      const data = await fetchSpendableData().catch((err) =>
        outputErrorAndExit(json, `Request failed: ${apiErrorMessage(err)}`),
      );
      outputData(json, {
        json: { walletAddress, wallet: data.walletBalancesJson },
        render: () => {},
      });
    } else if (live) {
      await renderLive(
        <BalanceView
          fetchData={fetchSpendableData}
          sort="usd-value"
          mode="wallet"
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
        />,
      );
    } else {
      const walletResult = await fetchWalletBalances(walletAddress).catch(
        (err) =>
          outputErrorAndExit(json, `Request failed: ${apiErrorMessage(err)}`),
      );
      renderWallet(json, walletAddress, walletResult);
    }
  });

balanceCommand
  .command("coins")
  .description("Show coin positions")
  .option("--sort <sort>", `Sort by: ${SORT_OPTIONS}`, "usd-value")
  .option("--limit <n>", "Number of results (max 20)", "10")
  .option("--live", "Interactive live-updating display (default)")
  .option("--static", "Static snapshot")
  .option(
    "--refresh <seconds>",
    "Auto-refresh interval in seconds, requires --live (min 5)",
    "30",
  )
  .option("--after <cursor>", "Pagination cursor from a previous result")
  .action(async function (this: Command, opts) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    const { sort, limit } = validateCoinOpts(json, opts.sort, opts.limit);
    const after: string | undefined = opts.after;
    const { account, smartWalletAccount, hasApiKey } = await resolveContext();
    const { live, intervalSeconds } = getLiveConfig(this, output);

    const walletAddress = smartWalletAccount?.address ?? account.address;

    const fetchCoinsPage = async (
      cursor?: string,
    ): Promise<PageResult<BalanceNode>> => {
      const { balances, total, pageInfo } = await fetchCoins(
        json,
        walletAddress,
        sort,
        limit,
        cursor,
      );
      return { items: balances, count: total, pageInfo };
    };

    if (json) {
      const { items, count, pageInfo } = await fetchCoinsPage(after);
      renderCoins(
        json,
        walletAddress,
        items,
        count ?? items.length,
        sort,
        limit,
        pageInfo,
      );
    } else if (live) {
      await renderLive(
        <BalanceCoinsView
          fetchPage={fetchCoinsPage}
          sort={sort}
          limit={limit}
          initialCursor={after}
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
          hasApiKey={hasApiKey}
        />,
      );
    } else {
      const { balances, total, pageInfo } = await fetchCoins(
        json,
        walletAddress,
        sort,
        limit,
        after,
      );
      renderCoins(
        json,
        walletAddress,
        balances,
        total,
        sort,
        limit,
        pageInfo,
        hasApiKey,
      );
    }
  });
