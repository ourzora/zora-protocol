import { Command } from "commander";
import { Box, Text } from "ink";
import { getProfileBalances, setApiKey } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import {
  getOutputMode,
  getLiveConfig,
  outputData,
  outputErrorAndExit,
} from "../lib/output.js";
import { renderOnce, renderLive } from "../lib/render.js";
import { BalanceView, type BalanceData } from "../components/BalanceView.js";
import { Table } from "../components/table.js";
import { resolveAccount } from "../lib/wallet.js";
import {
  parseRawBalance,
  normalizeTokenAmount,
} from "../lib/balance-format.js";
import {
  fetchWalletBalances,
  type WalletBalance,
  type WalletBalanceJson,
} from "../lib/wallet-balances.js";
import { track } from "../lib/analytics.js";
import {
  walletColumns,
  balanceColumns,
  SORT_LABELS,
  type SortFlag,
  type BalanceNode,
} from "../lib/balance-columns.js";

export {
  walletColumns,
  balanceColumns,
  SORT_LABELS,
  type SortFlag,
  type BalanceNode,
};

type FormattedBalanceJson = {
  rank: number;
  name: string | null;
  symbol: string | null;
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

const extractErrorMessage = (error: unknown): string => {
  if (typeof error === "object" && error !== null && "error" in error) {
    return String((error as Record<string, unknown>).error);
  }
  return JSON.stringify(error);
};

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
  const usdValue =
    priceUsdValue !== null
      ? Number((parseRawBalance(balance.balance) * priceUsdValue).toFixed(6))
      : null;
  const marketCapChange24h =
    marketCap !== null &&
    marketCapDelta24h !== null &&
    marketCap - marketCapDelta24h !== 0
      ? Number(
          ((marketCapDelta24h / (marketCap - marketCapDelta24h)) * 100).toFixed(
            4,
          ),
        )
      : null;

  return {
    rank,
    name: balance.coin?.name ?? null,
    symbol: balance.coin?.symbol ?? null,
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

function resolveContext(json: boolean) {
  const account = resolveAccount(json);

  const apiKey = getApiKey();
  if (!apiKey) {
    outputErrorAndExit(
      json,
      "Not authenticated. Run 'zora auth configure' to set your API key.",
    );
  }
  setApiKey(apiKey);

  return account;
}

function renderWallet(
  json: boolean,
  walletResult: Awaited<ReturnType<typeof fetchWalletBalances>>,
) {
  outputData(json, {
    json: { wallet: walletResult.walletBalancesJson },
    table: () => {
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
  balances: BalanceNode[],
  total: number,
  sort: SortFlag,
) {
  const rankedBalances = balances.map((balance, index) => ({
    ...balance,
    rank: index + 1,
  }));

  outputData(json, {
    json: {
      coins: rankedBalances.map((balance) =>
        formatBalanceJson(balance, balance.rank),
      ),
    },
    table: () => {
      if (balances.length === 0) {
        console.log("\n No coin balances found.\n");
        console.log(" Buy coins to see them here:");
        console.log("   zora buy <address> --eth 0.001\n");
      } else {
        renderOnce(
          <Table
            columns={balanceColumns}
            data={rankedBalances}
            title={`Coins · sorted by ${SORT_LABELS[sort]}`}
            subtitle={`${balances.length} of ${total}`}
          />,
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
) {
  let response: Awaited<ReturnType<typeof getProfileBalances>>;
  try {
    response = await getProfileBalances({
      identifier: address,
      count: limit,
      sortOption: SORT_MAP[sort],
    });
  } catch (err) {
    outputErrorAndExit(
      json,
      `Request failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  if (response.error) {
    outputErrorAndExit(
      json,
      `API error: ${extractErrorMessage(response.error)}`,
    );
  }

  const edges = response.data?.profile?.coinBalances?.edges ?? [];
  const balances: BalanceNode[] = edges.map(
    (e: { node: BalanceNode }) => e.node,
  );
  const total = response.data?.profile?.coinBalances?.count ?? balances.length;

  return { balances, total };
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
  .action(async function (this: Command) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    const account = resolveContext(json);
    const { live, intervalSeconds } = getLiveConfig(this, "live");

    const sort: SortFlag = "usd-value";
    const limit = 10;

    const fetchBalanceData = async (): Promise<BalanceData> => {
      const [walletResult, coinsResult] = await Promise.allSettled([
        fetchWalletBalances(account.address),
        fetchCoins(json, account.address, sort, limit),
      ]);

      if (
        walletResult.status === "rejected" ||
        coinsResult.status === "rejected"
      ) {
        const err =
          walletResult.status === "rejected"
            ? walletResult.reason
            : (coinsResult as PromiseRejectedResult).reason;
        throw new Error(err instanceof Error ? err.message : String(err));
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
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );

      outputData(json, {
        json: {
          wallet: data.walletBalancesJson,
          coins: data.rankedBalances.map((balance) =>
            formatBalanceJson(balance, balance.rank),
          ),
        },
        table: () => {},
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
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
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
            <Table
              columns={balanceColumns}
              data={data.rankedBalances}
              title={`Coins · sorted by ${SORT_LABELS[sort]}`}
              subtitle={`${data.rankedBalances.length} of ${data.total}`}
            />
          )}
        </Box>,
      );

      track("cli_balances", {
        sort,
        limit,
        live: false,
        result_count: data.rankedBalances.length,
        total_count: data.total,
        output_format: "text",
      });
    }
  });

balanceCommand
  .command("spendable")
  .description("Show wallet token balances (ETH, USDC, ZORA)")
  .action(async function (this: Command) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    const account = resolveContext(json);
    const { live, intervalSeconds } = getLiveConfig(this, "live");

    const fetchSpendableData = async (): Promise<BalanceData> => {
      const walletResult = await fetchWalletBalances(account.address);
      return {
        walletBalances: walletResult.walletBalances,
        walletBalancesJson: walletResult.walletBalancesJson,
        rankedBalances: [],
        total: 0,
      };
    };

    if (json) {
      const data = await fetchSpendableData().catch((err) =>
        outputErrorAndExit(
          json,
          `Request failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );
      outputData(json, {
        json: { wallet: data.walletBalancesJson },
        table: () => {},
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
      const walletResult = await fetchWalletBalances(account.address).catch(
        (err) =>
          outputErrorAndExit(
            json,
            `Request failed: ${err instanceof Error ? err.message : String(err)}`,
          ),
      );
      renderWallet(json, walletResult);
    }
  });

balanceCommand
  .command("coins")
  .description("Show coin positions")
  .option("--sort <sort>", `Sort by: ${SORT_OPTIONS}`, "usd-value")
  .option("--limit <n>", "Number of results (max 20)", "10")
  .action(async function (this: Command, opts) {
    const output = getOutputMode(this, "live");
    const json = output === "json";
    const { sort, limit } = validateCoinOpts(json, opts.sort, opts.limit);
    const account = resolveContext(json);
    const { live, intervalSeconds } = getLiveConfig(this, "live");

    const fetchCoinsData = async (): Promise<BalanceData> => {
      const { balances, total } = await fetchCoins(
        json,
        account.address,
        sort,
        limit,
      );
      const rankedBalances = balances.map((balance, index) => ({
        ...balance,
        rank: index + 1,
      }));
      return {
        walletBalances: [],
        walletBalancesJson: [],
        rankedBalances,
        total,
      };
    };

    if (json) {
      const data = await fetchCoinsData();
      renderCoins(json, data.rankedBalances, data.total, sort);
    } else if (live) {
      await renderLive(
        <BalanceView
          fetchData={fetchCoinsData}
          sort={sort}
          mode="coins"
          autoRefresh={live}
          intervalSeconds={intervalSeconds}
        />,
      );
    } else {
      const { balances, total } = await fetchCoins(
        json,
        account.address,
        sort,
        limit,
      );
      renderCoins(json, balances, total, sort);
    }
  });
