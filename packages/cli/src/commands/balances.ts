import { Command } from "commander";
import { getProfileBalances, setApiKey } from "@zoralabs/coins-sdk";
import { privateKeyToAccount } from "viem/accounts";
import { getApiKey, getPrivateKey } from "../lib/config.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { renderOnce } from "../lib/render.js";
import { TableComponent, type Column } from "../components/table.js";
import { formatCompactCurrency, formatChange } from "./explore.jsx";

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

const SORT_MAP: Record<SortFlag, "USD_VALUE" | "BALANCE" | "MARKET_CAP" | "PRICE_CHANGE"> = {
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

const normalizeKey = (key: string): `0x${string}` =>
  (key.startsWith("0x") ? key : `0x${key}`) as `0x${string}`;

const resolveAccount = (json: boolean): ReturnType<typeof privateKeyToAccount> => {
  const envKey = process.env.ZORA_PRIVATE_KEY;
  const key = envKey || getPrivateKey();

  if (!key) {
    outputErrorAndExit(json, "No wallet configured.", "Run 'zora setup' to create or import one.");
  }

  try {
    return privateKeyToAccount(normalizeKey(key));
  } catch {
    outputErrorAndExit(
      json,
      "Private key is invalid.",
      "Please correctly set up your private key. See `zora wallet` for more info.",
    );
  }
};

const COIN_DECIMALS = 18;

export function toHumanBalance(rawBalance: string): number {
  return Number(normalizeTokenAmount(rawBalance));
}

export function normalizeTokenAmount(rawBalance: string, decimals = COIN_DECIMALS): string {
  try {
    const value = BigInt(rawBalance);
    const divisor = 10n ** BigInt(decimals);
    const whole = value / divisor;
    const fraction = value % divisor;

    if (fraction === 0n) return whole.toString();

    const fractionText = fraction.toString().padStart(decimals, "0").replace(/0+$/, "");
    return `${whole}.${fractionText}`;
  } catch {
    return rawBalance;
  }
}

export function formatUsdValue(balance: string, priceInUsdc?: string): string {
  if (!priceInUsdc) return "-";
  const value = toHumanBalance(balance) * Number(priceInUsdc);
  if (value < 0.01) return "<$0.01";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatBalance(balance: string): string {
  const n = toHumanBalance(balance);
  if (n === 0) return "0";
  if (n < 0.001) return "<0.001";
  if (n < 1) return n.toFixed(4);
  return new Intl.NumberFormat("en-US", {
    notation: "compact",
    compactDisplay: "long",
    maximumFractionDigits: 1,
  }).format(n);
}

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

const balanceColumns: Column<BalanceNode & { rank: number }>[] = [
  { header: "#", width: 5, accessor: (row) => String(row.rank) },
  { header: "Name", width: 24, accessor: (row) => row.coin?.name ?? "Unknown" },
  { header: "Symbol", width: 12, noTruncate: true, accessor: (row) => row.coin?.symbol ?? "" },
  { header: "Balance", width: 14, accessor: (row) => formatBalance(row.balance) },
  {
    header: "USD Value",
    width: 14,
    accessor: (row) => formatUsdValue(row.balance, row.coin?.tokenPrice?.priceInUsdc),
  },
  {
    header: "Market Cap",
    width: 14,
    accessor: (row) => formatCompactCurrency(row.coin?.marketCap),
  },
  {
    header: "24h Change",
    width: 12,
    accessor: (row) => formatChange(row.coin?.marketCap, row.coin?.marketCapDelta24h),
    color: changeColor,
  },
];

const formatBalanceJson = (balance: BalanceNode, rank: number): FormattedBalanceJson => {
  const priceUsd = balance.coin?.tokenPrice?.priceInUsdc;
  const marketCap = balance.coin?.marketCap ? Number(balance.coin.marketCap) : null;
  const marketCapDelta24h = balance.coin?.marketCapDelta24h ? Number(balance.coin.marketCapDelta24h) : null;
  const volume24h = balance.coin?.volume24h ? Number(balance.coin.volume24h) : null;
  const totalVolume = balance.coin?.totalVolume ? Number(balance.coin.totalVolume) : null;
  const priceUsdValue = priceUsd ? Number(priceUsd) : null;
  const usdValue = priceUsdValue !== null ? Number((toHumanBalance(balance.balance) * priceUsdValue).toFixed(6)) : null;
  const marketCapChange24h =
    marketCap !== null && marketCapDelta24h !== null && marketCap - marketCapDelta24h !== 0
      ? Number((((marketCapDelta24h / (marketCap - marketCapDelta24h)) * 100)).toFixed(4))
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

export const balancesCommand = new Command("balances")
  .description("Show coin balances in your wallet")
  .option("--sort <sort>", `Sort by: ${SORT_OPTIONS}`, "usd-value")
  .option("--limit <n>", "Number of results (max 20)", "10")
  .action(async function (this: Command, opts) {
    const json = getJson(this);
    const sort = opts.sort as SortFlag;
    const limit = parseInt(opts.limit, 10);

    if (!SORT_MAP[sort]) {
      outputErrorAndExit(json, `Invalid --sort value: ${sort}.`, `Supported: ${SORT_OPTIONS}`);
    }

    if (isNaN(limit) || limit <= 0 || limit > 20) {
      outputErrorAndExit(json, `Invalid --limit value: ${opts.limit}. Must be an integer between 1 and 20.`);
    }

    const account = resolveAccount(json);

    const apiKey = getApiKey();
    if (!apiKey) {
      outputErrorAndExit(json, "Not authenticated. Run 'zora auth configure' to set your API key.");
    }
    setApiKey(apiKey);

    let response: Awaited<ReturnType<typeof getProfileBalances>>;
    try {
      response = await getProfileBalances({
        identifier: account.address,
        count: limit,
        sortOption: SORT_MAP[sort],
      });
    } catch (err) {
      outputErrorAndExit(json, `Request failed: ${err instanceof Error ? err.message : String(err)}`);
    }

    if (response.error) {
      const msg =
        typeof response.error === "object" && (response.error as any).error
          ? (response.error as any).error
          : JSON.stringify(response.error);
      outputErrorAndExit(json, `API error: ${msg}`);
    }

    const edges = response.data?.profile?.coinBalances?.edges ?? [];
    const balances: BalanceNode[] = edges.map((e: any) => e.node);

    if (balances.length === 0) {
      outputData(json, {
        json: [],
        table: () => {
          console.log("\n No coin balances found.\n");
          console.log(" Buy coins to see them here:");
          console.log("   zora buy <address> --eth 0.001\n");
        },
      });
      return;
    }

    const total = response.data?.profile?.coinBalances?.count ?? balances.length;
    const rankedBalances = balances.map((balance, index) => ({ ...balance, rank: index + 1 }));

    outputData(json, {
      json: rankedBalances.map((balance) => formatBalanceJson(balance, balance.rank)),
      table: () => {
        renderOnce(
          TableComponent<BalanceNode & { rank: number }>({
            columns: balanceColumns,
            data: rankedBalances,
            title: `Wallet Balances · sorted by ${SORT_LABELS[sort]}`,
            subtitle: `${balances.length} of ${total}`,
          }),
        );
      },
    });
  });
