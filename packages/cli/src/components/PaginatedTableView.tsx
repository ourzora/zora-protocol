import {
  useState,
  useEffect,
  useCallback,
  useRef,
  type ReactNode,
} from "react";
import { Box, Text, useInput, useApp } from "ink";
import Spinner from "ink-spinner";
import { Table, type Column } from "./table.js";
import type { PageInfo } from "../lib/types.js";
import { useAutoRefresh } from "../hooks/use-auto-refresh.js";
import { copyToClipboard } from "../lib/clipboard.js";

type PageResult<T> = {
  items: T[];
  pageInfo?: PageInfo;
  count?: number;
};

type CachedPage<T> = {
  result: PageResult<T>;
  fetchedAt: number;
};

const CACHE_KEY_FIRST = "__first__";
const CACHE_TTL_MS = 60_000;

type PaginatedTableViewProps<T> = {
  fetchPage: (cursor?: string) => Promise<PageResult<T>>;
  columns: Column<T & { rank: number }>[];
  title: string;
  loadingText: string;
  emptyState: ReactNode;
  getAddress: (item: T) => string | undefined;
  limit?: number;
  initialCursor?: string;
  autoRefresh?: boolean;
  intervalSeconds?: number;
  formatSubtitle?: (info: {
    page: number;
    itemCount: number;
    total: number;
  }) => string;
};

function PaginatedTableView<T>({
  fetchPage,
  columns,
  title,
  loadingText,
  emptyState,
  getAddress,
  limit = 10,
  initialCursor,
  autoRefresh = false,
  intervalSeconds = 30,
  formatSubtitle,
}: PaginatedTableViewProps<T>) {
  const { exit } = useApp();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [items, setItems] = useState<T[]>([]);
  const [total, setTotal] = useState(0);
  const [pageInfo, setPageInfo] = useState<PageInfo | null>(null);
  const [page, setPage] = useState(1);
  const targetPage = useRef(1);
  const [cursorHistory, setCursorHistory] = useState<(string | undefined)[]>(
    [],
  );
  const [currentCursor, setCurrentCursor] = useState<string | undefined>(
    initialCursor,
  );
  const cache = useRef<Map<string, CachedPage<T>>>(new Map());
  const { refreshCount, secondsUntilRefresh, triggerManualRefresh } =
    useAutoRefresh(intervalSeconds, autoRefresh);
  const [selectedRow, setSelectedRow] = useState(0);
  const [copyFeedback, setCopyFeedback] = useState<string | null>(null);

  useEffect(() => {
    setSelectedRow((r) => Math.min(r, Math.max(0, items.length - 1)));
  }, [items.length]);

  const loadPage = useCallback(
    async (cursor?: string) => {
      const cacheKey = cursor ?? CACHE_KEY_FIRST;
      const cached = cache.current.get(cacheKey);
      const isFresh = cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS;

      if (isFresh) {
        setItems(cached.result.items);
        setTotal(cached.result.count ?? cached.result.items.length);
        setPageInfo(cached.result.pageInfo ?? null);
        setPage(targetPage.current);
        setError(null);
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);
      try {
        const result = await fetchPage(cursor);
        cache.current.set(cacheKey, { result, fetchedAt: Date.now() });
        setItems(result.items);
        setTotal(result.count ?? result.items.length);
        setPageInfo(result.pageInfo ?? null);
        setPage(targetPage.current);
      } catch (err) {
        setError(err instanceof Error ? err.message : String(err));
      }
      setLoading(false);
    },
    [fetchPage],
  );

  // Clear cache for current page on auto-refresh tick
  useEffect(() => {
    if (refreshCount === 0) return;
    const cacheKey = currentCursor ?? CACHE_KEY_FIRST;
    cache.current.delete(cacheKey);
  }, [refreshCount, currentCursor]);

  useEffect(() => {
    loadPage(currentCursor);
  }, [currentCursor, loadPage, refreshCount]);

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
      setSelectedRow((r) => Math.min(items.length - 1, r + 1));
      return;
    }

    if (input === "c" || key.return) {
      const item = items[selectedRow];
      if (item) {
        const address = getAddress(item);
        if (address) {
          const ok = copyToClipboard(address);
          setCopyFeedback(ok ? "Copied!" : "Copy failed");
          setTimeout(() => setCopyFeedback(null), 1500);
        }
      }
      return;
    }

    const canGoNext = pageInfo?.hasNextPage && pageInfo.endCursor;
    const canGoPrev = cursorHistory.length > 0;

    if ((input === "n" || key.rightArrow) && canGoNext) {
      setCursorHistory((prev) => [...prev, currentCursor]);
      setCurrentCursor(pageInfo?.endCursor);
      targetPage.current += 1;
      setSelectedRow(0);
    }

    if ((input === "p" || key.leftArrow) && canGoPrev) {
      const prev = cursorHistory[cursorHistory.length - 1];
      setCursorHistory((h) => h.slice(0, -1));
      setCurrentCursor(prev);
      targetPage.current -= 1;
      setSelectedRow(0);
    }

    if (input === "r") {
      const cacheKey = currentCursor ?? CACHE_KEY_FIRST;
      cache.current.delete(cacheKey);
      triggerManualRefresh();
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
          <Spinner type="dots" /> {loadingText}
        </Text>
      </Box>
    );
  }

  if (items.length === 0) {
    return <>{emptyState}</>;
  }

  const rankedItems = items.map((item, i) => ({
    ...item,
    rank: (page - 1) * limit + i + 1,
  }));
  const subtitle = formatSubtitle
    ? formatSubtitle({ page, itemCount: items.length, total })
    : `Page ${page} \u00b7 ${items.length} of ${total}`;

  const hints: string[] = [];
  hints.push("\u2191\u2193 select");
  hints.push("enter/c copy address");
  if (cursorHistory.length > 0) hints.push("\u2190 prev");
  if (pageInfo?.hasNextPage) hints.push("\u2192 next");
  hints.push(autoRefresh ? `r refresh (${secondsUntilRefresh}s)` : "r refresh");
  hints.push("q quit");
  const footer =
    hints.join("  \u00b7  ") + (copyFeedback ? `  ${copyFeedback}` : "");

  return (
    <Table
      data={rankedItems}
      columns={columns}
      title={title}
      subtitle={subtitle}
      footer={footer}
      selectedRow={selectedRow}
    />
  );
}

export { PaginatedTableView, type PaginatedTableViewProps, type PageResult };
