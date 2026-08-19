import { Box, Text } from "ink";
import { type Column } from "./table.js";
import { PaginatedTableView, type PageResult } from "./PaginatedTableView.js";
import {
  formatCompactUsd,
  formatRelativeTime,
  formatCoinsDisplay,
} from "../lib/format.js";
import { COIN_TYPE_DISPLAY } from "../lib/types.js";

type TradeNode = {
  transactionHash: string;
  blockTimestamp: string;
  coinAmount: string;
  swapActivityType?: "BUY" | "SELL";
  coin?: {
    address: string;
    name: string;
    symbol: string;
    coinType: "CREATOR" | "CONTENT" | "TREND";
  };
  currencyAmountWithPrice: {
    amountUsd?: string;
  };
};

const tradeColumns: Column<TradeNode & { rank: number }>[] = [
  { header: "#", width: 4, accessor: (t) => String(t.rank) },
  {
    header: "Side",
    width: 6,
    accessor: (t) => t.swapActivityType ?? "-",
    color: (t) =>
      t.swapActivityType === "BUY"
        ? "green"
        : t.swapActivityType === "SELL"
          ? "red"
          : undefined,
  },
  {
    header: "Coin",
    width: 18,
    accessor: (t) => t.coin?.name ?? "Unknown",
  },
  {
    header: "Type",
    width: 10,
    accessor: (t) =>
      COIN_TYPE_DISPLAY[t.coin?.coinType ?? ""] ?? t.coin?.coinType ?? "",
  },
  {
    header: "Amount",
    width: 14,
    accessor: (t) => formatCoinsDisplay(t.coinAmount),
  },
  {
    header: "USD Value",
    width: 12,
    accessor: (t) => formatCompactUsd(t.currencyAmountWithPrice.amountUsd),
  },
  {
    header: "When",
    width: 16,
    accessor: (t) => {
      if (!t.blockTimestamp) return "-";
      const date = new Date(t.blockTimestamp);
      if (isNaN(date.getTime())) return "-";
      return formatRelativeTime(date);
    },
  },
];

type ProfileTradesViewProps = {
  fetchPage: (cursor?: string) => Promise<PageResult<TradeNode>>;
  identifier: string;
  limit: number;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const emptyState = (
  <Box flexDirection="column" paddingLeft={1} paddingTop={1} paddingBottom={1}>
    <Text>No trades found for this profile.</Text>
    <Box marginTop={1}>
      <Text dimColor>Press q to exit</Text>
    </Box>
  </Box>
);

const ProfileTradesView = ({
  fetchPage,
  identifier,
  limit,
  autoRefresh,
  intervalSeconds,
}: ProfileTradesViewProps) => {
  return (
    <PaginatedTableView<TradeNode>
      fetchPage={fetchPage}
      columns={tradeColumns}
      title={`Trades · ${identifier}`}
      loadingText="Loading trades…"
      emptyState={emptyState}
      getAddress={(trade) => trade.coin?.address}
      limit={limit}
      autoRefresh={autoRefresh}
      intervalSeconds={intervalSeconds}
    />
  );
};

export {
  ProfileTradesView,
  tradeColumns,
  type ProfileTradesViewProps,
  type TradeNode,
};
