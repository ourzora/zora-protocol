import { Box, Text } from "ink";
import { type Column } from "./table.js";
import { PaginatedTableView, type PageResult } from "./PaginatedTableView.js";
import {
  formatCompactUsd,
  formatMcapChange,
  formatCoinType,
  formatCoinName,
  truncateAddress,
} from "../lib/format.js";
import {
  SORT_LABELS,
  TYPE_LABELS,
  type SortOption,
  type TypeOption,
  type CoinNode,
} from "../lib/types.js";

const COLUMNS: Column<CoinNode & { rank: number }>[] = [
  { header: "#", width: 4, accessor: (c) => String(c.rank) },
  {
    header: "Name",
    width: 20,
    accessor: (c) => formatCoinName(c),
  },
  {
    header: "Address",
    width: 14,
    accessor: (c) => (c.address ? truncateAddress(c.address) : ""),
  },
  {
    header: "Type",
    width: 14,
    accessor: (c) => formatCoinType(c.coinType),
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

type ExploreViewProps = {
  fetchPage: (cursor?: string) => Promise<PageResult<CoinNode>>;
  sort: SortOption;
  type: TypeOption;
  limit: number;
  initialCursor?: string;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const emptyState = (
  <Box flexDirection="column" paddingLeft={1} paddingTop={1} paddingBottom={1}>
    <Text>No coins found.</Text>
    <Box marginTop={1} flexDirection="column">
      <Text dimColor>Try a different sort or type:</Text>
      <Text dimColor> zora explore --sort volume --type all</Text>
      <Text dimColor> zora explore --sort new --type all</Text>
    </Box>
    <Box marginTop={1}>
      <Text dimColor>Press q to exit</Text>
    </Box>
  </Box>
);

const ExploreView = ({
  fetchPage,
  sort,
  type,
  limit,
  initialCursor,
  autoRefresh = false,
  intervalSeconds = 30,
}: ExploreViewProps) => {
  const title =
    type !== "all"
      ? `${SORT_LABELS[sort]} \u00b7 ${TYPE_LABELS[type]}`
      : SORT_LABELS[sort];

  const formatSubtitle = ({
    page,
    itemCount,
  }: {
    page: number;
    itemCount: number;
    total: number;
  }) => `Page ${page} \u00b7 ${itemCount} result${itemCount !== 1 ? "s" : ""}`;

  return (
    <PaginatedTableView<CoinNode>
      fetchPage={fetchPage}
      columns={COLUMNS}
      title={title}
      loadingText="Loading…"
      emptyState={emptyState}
      getAddress={(coin) => coin.address}
      limit={limit}
      initialCursor={initialCursor}
      autoRefresh={autoRefresh}
      intervalSeconds={intervalSeconds}
      formatSubtitle={formatSubtitle}
    />
  );
};

export { ExploreView, type ExploreViewProps };
