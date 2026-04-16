import { useState, useEffect, useCallback, useRef } from "react";
import { Box, Text, useInput, useApp } from "ink";
import Spinner from "ink-spinner";
import { CoinDetail } from "./CoinDetail.js";
import { PriceHistory } from "./PriceHistory.js";
import type { ResolvedCoin } from "../lib/coin-ref.js";
import type { Interval } from "../lib/price-history.js";
import { useAutoRefresh } from "../hooks/use-auto-refresh.js";

export type PriceHistoryData = {
  high: string;
  low: string;
  change: { text: string; color: "green" | "red" | undefined };
  sparklineText: string;
  interval: Interval;
};

export type CoinViewData = {
  coin: ResolvedCoin;
  priceHistory: PriceHistoryData | null;
};

const TAB_NAMES = ["Price History"] as const;
type TabIndex = 0;

type CoinViewProps = {
  fetchData: () => Promise<CoinViewData>;
  initialData?: CoinViewData;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const CoinView = ({
  fetchData,
  initialData,
  autoRefresh = false,
  intervalSeconds = 30,
}: CoinViewProps) => {
  const { exit } = useApp();
  const [activeTab, setActiveTab] = useState<TabIndex>(0);
  const [loading, setLoading] = useState(!initialData);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<CoinViewData | null>(initialData ?? null);

  const { refreshCount, secondsUntilRefresh, triggerManualRefresh } =
    useAutoRefresh(intervalSeconds, autoRefresh);
  const [manualRefreshCount, setManualRefreshCount] = useState(0);
  const hasLoadedOnce = useRef(!!initialData);

  const load = useCallback(async () => {
    if (hasLoadedOnce.current) {
      setIsRefreshing(true);
    } else {
      setLoading(true);
    }
    setError(null);
    try {
      const result = await fetchData();
      setData(result);
      hasLoadedOnce.current = true;
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
    setLoading(false);
    setIsRefreshing(false);
  }, [fetchData]);

  useEffect(() => {
    if (initialData && refreshCount === 0 && manualRefreshCount === 0) return;
    load();
  }, [load, refreshCount, manualRefreshCount]);

  useInput((input, key) => {
    if (input === "q" || key.escape) {
      exit();
      return;
    }
    if (input === "r" && !loading) {
      triggerManualRefresh();
      setManualRefreshCount((c) => c + 1);
    }
    if (key.leftArrow || input === "1") {
      setActiveTab(0);
    }
    // Ready for future tabs:
    // if (key.rightArrow || input === "2") setActiveTab(1);
  });

  if (error && !data) {
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

  if (loading && !data) {
    return (
      <Box paddingLeft={1} paddingTop={1}>
        <Text>
          <Spinner type="dots" /> Loading coin…
        </Text>
      </Box>
    );
  }

  if (!data) return null;

  const hints: string[] = [];
  if (TAB_NAMES.length > 1) {
    hints.push("\u2190 \u2192 switch tab");
  }
  hints.push(autoRefresh ? `r refresh (${secondsUntilRefresh}s)` : "r refresh");
  hints.push("q quit");
  const footer = hints.join("  \u00b7  ");

  const renderTab = () => {
    switch (activeTab) {
      case 0:
        return data.priceHistory ? (
          <PriceHistory
            coin={data.coin.name}
            coinType={data.coin.coinType}
            interval={data.priceHistory.interval}
            high={data.priceHistory.high}
            low={data.priceHistory.low}
            change={data.priceHistory.change}
            sparklineText={data.priceHistory.sparklineText}
            compact
          />
        ) : (
          <Box
            flexDirection="column"
            paddingLeft={1}
            paddingTop={1}
            paddingBottom={1}
          >
            <Text>No price data available.</Text>
          </Box>
        );
    }
  };

  return (
    <Box flexDirection="column">
      {isRefreshing && (
        <Box paddingLeft={1}>
          <Text dimColor>
            <Spinner type="dots" /> Refreshing…
          </Text>
        </Box>
      )}

      {error && data && (
        <Box paddingLeft={1}>
          <Text color="yellow">⚠ Refresh failed: {error}</Text>
        </Box>
      )}

      <CoinDetail coin={data.coin} />

      <Box paddingLeft={1} gap={2}>
        {TAB_NAMES.map((name, i) => (
          <Text key={name} bold={activeTab === i} dimColor={activeTab !== i}>
            {activeTab === i ? `[${name}]` : name}
          </Text>
        ))}
      </Box>

      {renderTab()}

      <Box paddingLeft={1} paddingBottom={1}>
        <Text dimColor>{footer}</Text>
      </Box>
    </Box>
  );
};

export { CoinView };
export type { CoinViewProps };
