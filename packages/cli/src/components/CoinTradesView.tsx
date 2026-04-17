import { Box, Text } from "ink";
import { type Column } from "./table.js";
import { PaginatedTableView, type PageResult } from "./PaginatedTableView.js";
import {
  formatRelativeTime,
  formatCoinsDisplay,
  truncateAddress,
} from "../lib/format.js";

export type TradeSwapNode = {
  activityType?: "BUY" | "SELL";
  coinAmount: string;
  blockTimestamp: string;
  senderAddress: string;
  senderProfile?: { handle: string };
  currencyAmountWithPrice: { priceUsdc?: string };
  transactionHash: string;
};

function formatTradeUsd(priceUsdc: string | undefined): string {
  if (!priceUsdc) return "-";
  const value = Number(priceUsdc);
  if (value === 0) return "$0.00";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

const coinTradeColumns: Column<TradeSwapNode & { rank: number }>[] = [
  { header: "#", width: 4, accessor: (t) => String(t.rank) },
  {
    header: "Type",
    width: 6,
    accessor: (t) => t.activityType ?? "?",
    color: (t) =>
      t.activityType === "BUY"
        ? "green"
        : t.activityType === "SELL"
          ? "red"
          : undefined,
  },
  {
    header: "User",
    width: 18,
    accessor: (t) =>
      t.senderProfile?.handle ?? truncateAddress(t.senderAddress),
  },
  {
    header: "Amount",
    width: 22,
    accessor: (t) => {
      const prefix = t.activityType === "BUY" ? "+" : "-";
      return `${prefix}${formatCoinsDisplay(t.coinAmount)} coins`;
    },
  },
  {
    header: "Value",
    width: 12,
    accessor: (t) => formatTradeUsd(t.currencyAmountWithPrice.priceUsdc),
  },
  {
    header: "When",
    width: 14,
    accessor: (t) => {
      if (!t.blockTimestamp) return "-";
      const date = new Date(t.blockTimestamp);
      if (isNaN(date.getTime())) return "-";
      return formatRelativeTime(date);
    },
  },
];

type CoinTradesViewProps = {
  fetchPage: (cursor?: string) => Promise<PageResult<TradeSwapNode>>;
  coinName: string;
  limit: number;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const emptyState = (
  <Box flexDirection="column" paddingLeft={1} paddingTop={1} paddingBottom={1}>
    <Text>No trades found for this coin.</Text>
    <Box marginTop={1}>
      <Text dimColor>Press q to exit</Text>
    </Box>
  </Box>
);

const CoinTradesView = ({
  fetchPage,
  coinName,
  limit,
  autoRefresh,
  intervalSeconds,
}: CoinTradesViewProps) => {
  return (
    <PaginatedTableView<TradeSwapNode>
      fetchPage={fetchPage}
      columns={coinTradeColumns}
      title={`Recent trades \u00b7 ${coinName}`}
      loadingText="Loading trades…"
      emptyState={emptyState}
      getAddress={(trade) => trade.senderAddress}
      limit={limit}
      autoRefresh={autoRefresh}
      intervalSeconds={intervalSeconds}
    />
  );
};

export { CoinTradesView, coinTradeColumns, type CoinTradesViewProps };
