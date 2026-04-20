import { Box, Text } from "ink";
import { type Column } from "./table.js";
import { PaginatedTableView, type PageResult } from "./PaginatedTableView.js";
import { formatBalance, parseRawBalance } from "../lib/balance-format.js";

type HolderNode = {
  balance: string;
  ownerAddress: string;
  ownerProfile?: {
    handle: string;
  };
};

function formatPct(pct: number): string {
  if (pct < 0.01) return "<0.01%";
  return `${pct.toFixed(1)}%`;
}

type HolderColumnContext = {
  totalSupplyNum: number;
};

const makeHolderColumns = (
  ctx: HolderColumnContext,
): Column<HolderNode & { rank: number }>[] => [
  { header: "#", width: 5, accessor: (r) => String(r.rank) },
  {
    header: "Holder",
    width: 20,
    accessor: (r) => r.ownerProfile?.handle ?? r.ownerAddress,
  },
  {
    header: "Balance",
    width: 18,
    accessor: (r) => formatBalance(r.balance),
  },
  {
    header: "% Supply",
    width: 10,
    accessor: (r) => {
      if (ctx.totalSupplyNum <= 0) return "-";
      const balanceNum = parseRawBalance(r.balance);
      return formatPct((balanceNum / ctx.totalSupplyNum) * 100);
    },
  },
];

type CoinHoldersViewProps = {
  fetchPage: (cursor?: string) => Promise<PageResult<HolderNode>>;
  coinName: string;
  totalSupplyNum: number;
  limit: number;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const emptyState = (
  <Box flexDirection="column" paddingLeft={1} paddingTop={1} paddingBottom={1}>
    <Text>No holders found for this coin.</Text>
    <Box marginTop={1}>
      <Text dimColor>Press q to exit</Text>
    </Box>
  </Box>
);

const CoinHoldersView = ({
  fetchPage,
  coinName,
  totalSupplyNum,
  limit,
  autoRefresh,
  intervalSeconds,
}: CoinHoldersViewProps) => {
  const columns = makeHolderColumns({ totalSupplyNum });

  return (
    <PaginatedTableView<HolderNode>
      fetchPage={fetchPage}
      columns={columns}
      title={`Top holders · ${coinName}`}
      loadingText="Loading holders…"
      emptyState={emptyState}
      getAddress={(holder) => holder.ownerAddress}
      limit={limit}
      autoRefresh={autoRefresh}
      intervalSeconds={intervalSeconds}
    />
  );
};

export {
  CoinHoldersView,
  makeHolderColumns,
  type CoinHoldersViewProps,
  type HolderNode,
};
