import { useState, useEffect } from "react";
import { Box, Text } from "ink";
import Spinner from "ink-spinner";
import { TableComponent, type Column } from "./table.js";
import { formatCompactUsd, formatMcapChange, truncate } from "../lib/format.js";
import {
  SORT_LABELS,
  TYPE_LABELS,
  COIN_TYPE_DISPLAY,
  type SortOption,
  type TypeOption,
  type CoinNode,
} from "../lib/types.js";

const COLUMNS: Column<CoinNode & { rank: number }>[] = [
  { header: "#", width: 4, accessor: (c) => String(c.rank) },
  {
    header: "Name",
    width: 20,
    accessor: (c) => truncate(c.name ?? "Unknown", 18),
  },
  { header: "Address", width: 44, accessor: (c) => c.address ?? "" },
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
];

interface ExploreViewProps {
  fetchCoins: () => Promise<CoinNode[]>;
  sort: SortOption;
  type: TypeOption;
  onComplete: () => void;
  onError: (msg: string) => void;
}

export function ExploreView({
  fetchCoins,
  sort,
  type,
  onComplete,
  onError,
}: ExploreViewProps) {
  const [coins, setCoins] = useState<CoinNode[] | null>(null);

  useEffect(() => {
    fetchCoins()
      .then((data) => {
        setCoins(data);
      })
      .catch((err: unknown) => {
        onError(err instanceof Error ? err.message : String(err));
      });
  }, []);

  useEffect(() => {
    if (coins !== null) {
      // Let Ink render one frame then exit
      const timer = setTimeout(onComplete, 0);
      return () => clearTimeout(timer);
    }
  }, [coins]);

  if (coins === null) {
    return (
      <Box paddingLeft={1}>
        <Text>
          <Spinner type="dots" /> Loading coins...
        </Text>
      </Box>
    );
  }

  if (coins.length === 0) {
    return (
      <Box flexDirection="column" paddingLeft={1} marginTop={1}>
        <Text>No coins found.</Text>
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>
            Try a different sort or type (defaults to posts):
          </Text>
          <Text dimColor> zora explore --sort volume --type all</Text>
          <Text dimColor> zora explore --sort new --type all</Text>
        </Box>
      </Box>
    );
  }

  const header =
    type !== "all"
      ? `${SORT_LABELS[sort]} \u00b7 ${TYPE_LABELS[type]}`
      : SORT_LABELS[sort];
  const count = `${coins.length} result${coins.length !== 1 ? "s" : ""}`;
  const rankedCoins = coins.map((c, i) => ({ ...c, rank: i + 1 }));

  return (
    <TableComponent
      data={rankedCoins}
      columns={COLUMNS}
      title={header}
      subtitle={count}
    />
  );
}
