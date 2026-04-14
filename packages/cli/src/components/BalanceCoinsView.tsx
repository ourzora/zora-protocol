import { Box, Text } from "ink";
import { PaginatedTableView, type PageResult } from "./PaginatedTableView.js";
import {
  balanceColumns,
  SORT_LABELS,
  type BalanceNode,
  type SortFlag,
} from "../lib/balance-columns.js";

type BalanceCoinsViewProps = {
  fetchPage: (cursor?: string) => Promise<PageResult<BalanceNode>>;
  sort: SortFlag;
  limit: number;
  initialCursor?: string;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const emptyState = (
  <Box flexDirection="column" paddingLeft={1} paddingTop={1} paddingBottom={1}>
    <Text>No coin balances found.</Text>
    <Box marginTop={1} flexDirection="column">
      <Text dimColor>Buy coins to see them here:</Text>
      <Text dimColor> zora buy {"<address>"} --eth 0.001</Text>
    </Box>
    <Box marginTop={1}>
      <Text dimColor>Press q to exit</Text>
    </Box>
  </Box>
);

const BalanceCoinsView = ({
  fetchPage,
  sort,
  limit,
  initialCursor,
  autoRefresh,
  intervalSeconds,
}: BalanceCoinsViewProps) => {
  return (
    <PaginatedTableView<BalanceNode>
      fetchPage={fetchPage}
      columns={balanceColumns}
      title={`Coins \u00b7 sorted by ${SORT_LABELS[sort]}`}
      loadingText="Loading…"
      emptyState={emptyState}
      getAddress={(item) => item.coin?.address}
      limit={limit}
      initialCursor={initialCursor}
      autoRefresh={autoRefresh}
      intervalSeconds={intervalSeconds}
    />
  );
};

export { BalanceCoinsView, type BalanceCoinsViewProps };
