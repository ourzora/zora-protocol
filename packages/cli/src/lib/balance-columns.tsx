import type { Column } from "../components/table.js";
import {
  formatCompactUsd,
  formatMcapChange,
  formatUsd,
  formatCoinType,
  formatCoinName,
  truncateAddress,
} from "./format.js";
import { formatBalance, computeBalanceUsdValue } from "./balance-format.js";
import type { WalletBalance } from "./wallet-balances.js";

type SortFlag = "usd-value" | "balance" | "market-cap" | "price-change";

type BalanceValuation = {
  marketValueUsd?: string;
  faceValueUsd?: string;
  blockNumber?: number;
};

type BalanceNode = {
  balance: string;
  valuation?: BalanceValuation;
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

const SORT_LABELS: Record<SortFlag, string> = {
  "usd-value": "USD Value",
  balance: "Balance",
  "market-cap": "Market Cap",
  "price-change": "Price Change",
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
  {
    header: "Name",
    width: 20,
    accessor: (row) => formatCoinName(row.coin),
  },
  {
    header: "Address",
    width: 14,
    accessor: (row) =>
      row.coin?.address ? truncateAddress(row.coin.address) : "",
  },
  {
    header: "Type",
    width: 14,
    accessor: (row) => formatCoinType(row.coin?.coinType),
  },
  {
    header: "Balance",
    width: 14,
    accessor: (row) => formatBalance(row.balance),
  },
  {
    header: "USD Value",
    width: 14,
    accessor: (row) => {
      const value = computeBalanceUsdValue(
        row.balance,
        row.valuation?.marketValueUsd,
        row.coin?.tokenPrice?.priceInUsdc,
      );
      if (value === null) return "-";
      if (value < 0.01) return "<$0.01";
      return formatUsd(value);
    },
  },
  {
    header: "Market Cap",
    width: 14,
    accessor: (row) => formatCompactUsd(row.coin?.marketCap),
  },
  {
    header: "24h Change",
    width: 12,
    accessor: (row) =>
      formatMcapChange(row.coin?.marketCap, row.coin?.marketCapDelta24h).text,
    color: (row) =>
      formatMcapChange(row.coin?.marketCap, row.coin?.marketCapDelta24h).color,
  },
];

const API_KEY_BANNER =
  "Valuation is more accurately evaluated when using an API key. Run `zora setup` to configure one.";

export {
  walletColumns,
  balanceColumns,
  SORT_LABELS,
  API_KEY_BANNER,
  type SortFlag,
  type BalanceNode,
  type BalanceValuation,
};
