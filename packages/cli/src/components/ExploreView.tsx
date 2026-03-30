import { useState, useEffect, useCallback, useRef } from "react";
import { Box, Text, useInput, useApp } from "ink";
import Spinner from "ink-spinner";
import { Table, type Column } from "./table.js";
import {
  formatCompactUsd,
  formatMcapChange,
  truncateAddress,
} from "../lib/format.js";
import {
  SORT_LABELS,
  TYPE_LABELS,
  COIN_TYPE_DISPLAY,
  type SortOption,
  type TypeOption,
  type CoinNode,
  type PageInfo,
} from "../lib/types.js";
import { useAutoRefresh } from "../hooks/use-auto-refresh.js";
import { copyToClipboard } from "../lib/clipboard.js";

const COLUMNS: Column<CoinNode & { rank: number }>[] = [
  { header: "#", width: 4, accessor: (c) => String(c.rank) },
  { header: "Name", width: 20, accessor: (c) => c.name ?? "Unknown" },
  {
    header: "Address",
    width: 14,
    accessor: (c) => (c.address ? truncateAddress(c.address) : ""),
  },
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
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const ExploreView = ({
  fetchPage,
  sort,
  type,
  limit,
  initialCursor,
  cacheTtlMs = CACHE_TTL_MS,
  autoRefresh = false,
  intervalSeconds = 30,
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
  const { refreshCount, secondsUntilRefresh, triggerManualRefresh } =
    useAutoRefresh(intervalSeconds, autoRefresh);
  const [manualRefreshCount, setManualRefreshCount] = useState(0);
  const [selectedRow, setSelectedRow] = useState(0);
  const [copyFeedback, setCopyFeedback] = useState<string | null>(null);

  useEffect(() => {
    setSelectedRow((r) => Math.min(r, Math.max(0, coins.length - 1)));
  }, [coins.length]);

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

  // Clear cache and re-fetch on auto-refresh tick
  useEffect(() => {
    if (refreshCount === 0) return;
    const cacheKey = currentCursor ?? CACHE_KEY_FIRST;
    cache.current.delete(cacheKey);
  }, [refreshCount, currentCursor]);

  useEffect(() => {
    loadPage(currentCursor);
  }, [currentCursor, loadPage, refreshCount, manualRefreshCount]);

  useInput((input, key) => {
    if (input === "q" || key.escape) {
      exit();
      return;
    }
    if (loading) return;

    if (key.upArrow || input === "k") {
      setSelectedRow((r) => Math.max(0, r - 1));
      return;
    }

    if (key.downArrow || input === "j") {
      setSelectedRow((r) => Math.min(coins.length - 1, r + 1));
      return;
    }

    if (input === "c") {
      const coin = coins[selectedRow];
      if (coin?.address) {
        const ok = copyToClipboard(coin.address);
        setCopyFeedback(ok ? "Copied!" : "Copy failed");
        setTimeout(() => setCopyFeedback(null), 1500);
      }
      return;
    }

    const canGoNext = pageInfo?.hasNextPage && pageInfo.endCursor;
    const canGoPrev = cursorHistory.length > 0;

    if ((input === "n" || key.rightArrow) && canGoNext) {
      setCursorHistory((prev) => [...prev, currentCursor]);
      setCurrentCursor(pageInfo!.endCursor);
      setPage((p) => p + 1);
      setSelectedRow(0);
    }

    if ((input === "p" || key.leftArrow) && canGoPrev) {
      const prev = cursorHistory[cursorHistory.length - 1];
      setCursorHistory((h) => h.slice(0, -1));
      setCurrentCursor(prev);
      setPage((p) => p - 1);
      setSelectedRow(0);
    }

    if (input === "r") {
      const cacheKey = currentCursor ?? CACHE_KEY_FIRST;
      cache.current.delete(cacheKey);
      triggerManualRefresh();
      setManualRefreshCount((c) => c + 1);
      setSelectedRow(0);
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
  hints.push("\u2191\u2193 select");
  hints.push("c copy address");
  if (cursorHistory.length > 0) hints.push("\u2190 prev");
  if (pageInfo?.hasNextPage) hints.push("\u2192 next");
  hints.push(autoRefresh ? `r refresh (${secondsUntilRefresh}s)` : "r refresh");
  hints.push("q quit");
  const footer =
    hints.join("  \u00b7  ") + (copyFeedback ? `  ${copyFeedback}` : "");

  return (
    <Table
      data={rankedCoins}
      columns={COLUMNS}
      title={title}
      subtitle={subtitle}
      footer={footer}
      selectedRow={selectedRow}
    />
  );
};

export { ExploreView, type ExploreViewProps, type ExplorePageResult };
