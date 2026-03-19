import { Command } from "commander";
import { getProfileBalances, setApiKey } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { renderOnce } from "../lib/render.js";
import { TableComponent, type Column } from "../components/table.js";
import { formatCompactCurrency, formatChange } from "./explore.jsx";
import { resolveAccount } from "../lib/wallet.js";
import {
  toHumanBalance,
  normalizeTokenAmount,
  formatUsdValue,
  formatBalance,
} from "../lib/balance-format.js";
import {
  fetchWalletBalances,
  type WalletBalance,
  type WalletBalanceJson,
} from "../lib/wallet-balances.js";

type SortFlag = "usd-value" | "balance" | "market-cap" | "price-change";
type BalanceNode = {
  balance: string;
  coin?: {
    address?: string;
    name?: string;
    symbol?: string;
    coinType?: string;
    chainId?: number;
    volume24h?: string;
    totalVolume?: string;
    marketCap?: string;
    marketCapDelta24h?: string;
    tokenPrice?: {
      priceInUsdc?: string;
    };
    creatorProfile?: {
      handle?: string;
    };
    mediaContent?: {
      previewImage?: {
        medium?: string;
      };
    };
  };
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

const SORT_LABELS: Record<SortFlag, string> = {
  "usd-value": "USD Value",
  balance: "Balance",
  "market-cap": "Market Cap",
  "price-change": "Price Change",
};

const SORT_OPTIONS = Object.keys(SORT_MAP).join(", ");

const extractErrorMessage = (error: unknown): string => {
  if (typeof error === "object" && error !== null && "error" in error) {
    return String((error as Record<string, unknown>).error);
  }
  return JSON.stringify(error);
};

const changeColor = (row: BalanceNode): string | undefined => {
  if (!row.coin?.marketCap || !row.coin.marketCapDelta24h) return undefined;
  const cap = Number(row.coin.marketCap);
  const d = Number(row.coin.marketCapDelta24h);
  if (cap === 0 || cap - d === 0) return undefined;
  const pct = (d / (cap - d)) * 100;
  if (pct > 0) return "green";
  if (pct < 0) return "red";
  return undefined;
};

const walletColumns: Column<WalletBalance>[] = [
  { header: "Name", width: 14, accessor: (row) => row.name },
  {
    header: "Symbol",
    width: 10,
    noTruncate: true,
    accessor: (row) => row.symbol,
  },
  { header: "Balance", width: 20, accessor: (row) => row.balance },
  { header: "USD Value", width: 16, accessor: (row) => row.usdValue },
];

const balanceColumns: Column<BalanceNode & { rank: number }>[] = [
  { header: "#", width: 5, accessor: (row) => String(row.rank) },
  { header: "Name", width: 24, accessor: (row) => row.coin?.name ?? "Unknown" },
  {
    header: "Symbol",
    width: 12,
    noTruncate: true,
    accessor: (row) => row.coin?.symbol ?? "",
  },
  {
    header: "Balance",
    width: 14,
    accessor: (row) => formatBalance(row.balance),
  },
  {
    header: "USD Value",
    width: 14,
    accessor: (row) =>
      formatUsdValue(row.balance, row.coin?.tokenPrice?.priceInUsdc),
  },
  {
    header: "Market Cap",
    width: 14,
    accessor: (row) => formatCompactCurrency(row.coin?.marketCap),
  },
  {
    header: "24h Change",
    width: 12,
    accessor: (row) =>
      formatChange(row.coin?.marketCap, row.coin?.marketCapDelta24h),
    color: changeColor,
  },
];

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
      ? Number((toHumanBalance(balance.balance) * priceUsdValue).toFixed(6))
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
        TableComponent<WalletBalance>({
          columns: walletColumns,
          data: walletResult.walletBalances,
          title: "Wallet",
        }),
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
          TableComponent<BalanceNode & { rank: number }>({
            columns: balanceColumns,
            data: rankedBalances,
            title: `Coins · sorted by ${SORT_LABELS[sort]}`,
            subtitle: `${balances.length} of ${total}`,
          }),
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
    const json = getJson(this);
    const account = resolveContext(json);

    const sort: SortFlag = "usd-value";
    const limit = 10;

    let walletResult: Awaited<ReturnType<typeof fetchWalletBalances>>;
    let coinsResult: { balances: BalanceNode[]; total: number };
    try {
      [walletResult, coinsResult] = await Promise.all([
        fetchWalletBalances(account.address),
        fetchCoins(json, account.address, sort, limit),
      ]);
    } catch (err) {
      outputErrorAndExit(
        json,
        `Request failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    const rankedBalances = coinsResult.balances.map((balance, index) => ({
      ...balance,
      rank: index + 1,
    }));

    outputData(json, {
      json: {
        wallet: walletResult.walletBalancesJson,
        coins: rankedBalances.map((balance) =>
          formatBalanceJson(balance, balance.rank),
        ),
      },
      table: () => {
        renderOnce(
          TableComponent<WalletBalance>({
            columns: walletColumns,
            data: walletResult.walletBalances,
            title: "Wallet",
          }),
        );

        if (coinsResult.balances.length === 0) {
          console.log("\n No coin balances found.\n");
          console.log(" Buy coins to see them here:");
          console.log("   zora buy <address> --eth 0.001\n");
        } else {
          renderOnce(
            TableComponent<BalanceNode & { rank: number }>({
              columns: balanceColumns,
              data: rankedBalances,
              title: `Coins · sorted by ${SORT_LABELS[sort]}`,
              subtitle: `${coinsResult.balances.length} of ${coinsResult.total}`,
            }),
          );
        }
      },
    });
  });

balanceCommand
  .command("spendable")
  .description("Show wallet token balances (ETH, USDC, ZORA)")
  .action(async function (this: Command) {
    const json = getJson(this);
    const account = resolveContext(json);

    let walletResult: Awaited<ReturnType<typeof fetchWalletBalances>>;
    try {
      walletResult = await fetchWalletBalances(account.address);
    } catch (err) {
      outputErrorAndExit(
        json,
        `Request failed: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    renderWallet(json, walletResult);
  });

balanceCommand
  .command("coins")
  .description("Show coin positions")
  .option("--sort <sort>", `Sort by: ${SORT_OPTIONS}`, "usd-value")
  .option("--limit <n>", "Number of results (max 20)", "10")
  .action(async function (this: Command, opts) {
    const json = getJson(this);
    const { sort, limit } = validateCoinOpts(json, opts.sort, opts.limit);
    const account = resolveContext(json);

    const { balances, total } = await fetchCoins(
      json,
      account.address,
      sort,
      limit,
    );

    renderCoins(json, balances, total, sort);
  });
