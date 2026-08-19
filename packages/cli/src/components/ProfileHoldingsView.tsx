import { Box, Text } from "ink";
import { PaginatedTableView, type PageResult } from "./PaginatedTableView.js";
import { balanceColumns, type BalanceNode } from "../lib/balance-columns.js";

type ProfileHoldingsViewProps = {
  fetchPage: (cursor?: string) => Promise<PageResult<BalanceNode>>;
  identifier: string;
  limit: number;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const emptyState = (
  <Box flexDirection="column" paddingLeft={1} paddingTop={1} paddingBottom={1}>
    <Text>No holdings found for this profile.</Text>
    <Box marginTop={1} flexDirection="column">
      <Text dimColor>Buy coins to see them here:</Text>
      <Text dimColor> zora buy {"<address>"} --eth 0.001</Text>
    </Box>
    <Box marginTop={1}>
      <Text dimColor>Press q to exit</Text>
    </Box>
  </Box>
);

const ProfileHoldingsView = ({
  fetchPage,
  identifier,
  limit,
  autoRefresh,
  intervalSeconds,
}: ProfileHoldingsViewProps) => {
  return (
    <PaginatedTableView<BalanceNode>
      fetchPage={fetchPage}
      columns={balanceColumns}
      title={`Holdings \u00b7 ${identifier}`}
      loadingText="Loading holdings…"
      emptyState={emptyState}
      getAddress={(holding) => holding.coin?.address}
      limit={limit}
      autoRefresh={autoRefresh}
      intervalSeconds={intervalSeconds}
    />
  );
};

export { ProfileHoldingsView, type ProfileHoldingsViewProps };
