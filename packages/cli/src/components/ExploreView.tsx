import { useState, useEffect, useCallback, useRef } from "react";
import { Box, Text, useInput, useApp } from "ink";
import Spinner from "ink-spinner";
import { Table, type Column } from "./table.js";
import { formatCompactUsd, formatMcapChange } from "../lib/format.js";
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
  { header: "Name", width: 20, accessor: (c) => c.name ?? "Unknown" },
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

type PageInfo = { endCursor?: string; hasNextPage: boolean };

type ExplorePageResult = {
  coins: CoinNode[];
  pageInfo?: PageInfo;
};

type CachedPage = {
  result: ExplorePageResult;
  fetchedAt: number;
};

const CACHE_TTL_MS = 60_000;
const CACHE_KEY_FIRST = "__first__";

type ExploreViewProps = {
  fetchPage: (cursor?: string) => Promise<ExplorePageResult>;
  sort: SortOption;
  type: TypeOption;
  limit: number;
  initialCursor?: string;
  cacheTtlMs?: number;
};

const ExploreView = ({
  fetchPage,
  sort,
  type,
  limit,
  initialCursor,
  cacheTtlMs = CACHE_TTL_MS,
}: ExploreViewProps) => {
  const { exit } = useApp();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [coins, setCoins] = useState<CoinNode[]>([]);
  const [pageInfo, setPageInfo] = useState<PageInfo | null>(null);
  const [page, setPage] = useState(1);
  const [cursorHistory, setCursorHistory] = useState<(string | undefined)[]>(
    [],
  );
  const [currentCursor, setCurrentCursor] = useState<string | undefined>(
    initialCursor,
  );
  const cache = useRef<Map<string, CachedPage>>(new Map());
  const [refreshCount, setRefreshCount] = useState(0);

  const loadPage = useCallback(
    async (cursor?: string) => {
      const cacheKey = cursor ?? CACHE_KEY_FIRST;
      const cached = cache.current.get(cacheKey);
      const isFresh = cached && Date.now() - cached.fetchedAt < cacheTtlMs;

      if (isFresh) {
        setCoins(cached.result.coins);
        setPageInfo(cached.result.pageInfo ?? null);
        setError(null);
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);
      try {
        const result = await fetchPage(cursor);
        cache.current.set(cacheKey, { result, fetchedAt: Date.now() });
        setCoins(result.coins);
        setPageInfo(result.pageInfo ?? null);
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      }
      setLoading(false);
    },
    [fetchPage, cacheTtlMs],
  );

  useEffect(() => {
    loadPage(currentCursor);
  }, [currentCursor, loadPage, refreshCount]);

  useInput((input, key) => {
    if (input === "q" || key.escape) {
      exit();
      return;
    }
    if (loading) return;

    const canGoNext = pageInfo?.hasNextPage && pageInfo.endCursor;
    const canGoPrev = cursorHistory.length > 0;

    if ((input === "n" || key.rightArrow) && canGoNext) {
      setCursorHistory((prev) => [...prev, currentCursor]);
      setCurrentCursor(pageInfo!.endCursor);
      setPage((p) => p + 1);
    }

    if ((input === "p" || key.leftArrow) && canGoPrev) {
      const prev = cursorHistory[cursorHistory.length - 1];
      setCursorHistory((h) => h.slice(0, -1));
      setCurrentCursor(prev);
      setPage((p) => p - 1);
    }

    if (input === "r") {
      const cacheKey = currentCursor ?? CACHE_KEY_FIRST;
      cache.current.delete(cacheKey);
      setRefreshCount((c) => c + 1);
    }
  });

  if (error) {
    return (
      <Box
        flexDirection="column"
        paddingLeft={1}
        paddingTop={1}
        paddingBottom={1}
      >
        <Text color="red">Error: {error}</Text>
        <Box marginTop={1}>
          <Text dimColor>Press q to exit</Text>
        </Box>
      </Box>
    );
  }

  if (loading) {
    return (
      <Box paddingLeft={1} paddingTop={1}>
        <Text>
          <Spinner type="dots" /> Loading…
        </Text>
      </Box>
    );
  }

  if (coins.length === 0) {
    return (
      <Box
        flexDirection="column"
        paddingLeft={1}
        paddingTop={1}
        paddingBottom={1}
      >
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
  }

  const title =
    type !== "all"
      ? `${SORT_LABELS[sort]} \u00b7 ${TYPE_LABELS[type]}`
      : SORT_LABELS[sort];
  const subtitle = `Page ${page} \u00b7 ${coins.length} result${coins.length !== 1 ? "s" : ""}`;
  const rankedCoins = coins.map((c, i) => ({
    ...c,
    rank: (page - 1) * limit + i + 1,
  }));

  const hints: string[] = [];
  if (cursorHistory.length > 0) hints.push("\u2190 prev");
  if (pageInfo?.hasNextPage) hints.push("\u2192 next");
  hints.push("r refresh");
  hints.push("q quit");
  const footer = hints.join("  \u00b7  ");

  return (
    <Table
      data={rankedCoins}
      columns={COLUMNS}
      title={title}
      subtitle={subtitle}
      footer={footer}
    />
  );
};

export { ExploreView, type ExploreViewProps, type ExplorePageResult };
