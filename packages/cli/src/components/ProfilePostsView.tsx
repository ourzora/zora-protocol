import { Box, Text } from "ink";
import { type Column } from "./table.js";
import { PaginatedTableView, type PageResult } from "./PaginatedTableView.js";
import {
  formatCompactUsd,
  formatMcapChange,
  formatRelativeTime,
} from "../lib/format.js";
import { COIN_TYPE_DISPLAY } from "../lib/types.js";

type PostNode = {
  name: string;
  address: string;
  coinType: "CREATOR" | "CONTENT" | "TREND";
  symbol: string;
  marketCap?: string;
  marketCapDelta24h?: string;
  volume24h?: string;
  createdAt?: string;
};

const postColumns: Column<PostNode & { rank: number }>[] = [
  { header: "#", width: 4, accessor: (c) => String(c.rank) },
  { header: "Name", width: 20, accessor: (c) => c.name ?? "Unknown" },
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
  {
    header: "Created",
    width: 16,
    accessor: (c) => {
      if (!c.createdAt) return "-";
      const date = new Date(c.createdAt);
      if (isNaN(date.getTime())) return "-";
      return formatRelativeTime(date);
    },
  },
];

type ProfilePostsViewProps = {
  fetchPage: (cursor?: string) => Promise<PageResult<PostNode>>;
  identifier: string;
  limit: number;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const emptyState = (
  <Box flexDirection="column" paddingLeft={1} paddingTop={1} paddingBottom={1}>
    <Text>No posts found for this profile.</Text>
    <Box marginTop={1}>
      <Text dimColor>Press q to exit</Text>
    </Box>
  </Box>
);

const ProfilePostsView = ({
  fetchPage,
  identifier,
  limit,
  autoRefresh,
  intervalSeconds,
}: ProfilePostsViewProps) => {
  return (
    <PaginatedTableView<PostNode>
      fetchPage={fetchPage}
      columns={postColumns}
      title={`Posts \u00b7 ${identifier}`}
      loadingText="Loading posts…"
      emptyState={emptyState}
      getAddress={(post) => post.address}
      limit={limit}
      autoRefresh={autoRefresh}
      intervalSeconds={intervalSeconds}
    />
  );
};

export {
  ProfilePostsView,
  postColumns,
  type ProfilePostsViewProps,
  type PostNode,
};
