import { useState, useEffect, useCallback, useRef } from "react";
import { Box, Text, useInput, useApp } from "ink";
import Spinner from "ink-spinner";
import { Table } from "./table.js";
import { postColumns, type PostNode } from "./ProfilePostsView.js";
import { tradeColumns, type TradeNode } from "./ProfileTradesView.js";
import { balanceColumns, type BalanceNode } from "../lib/balance-columns.js";
import { useAutoRefresh } from "../hooks/use-auto-refresh.js";

type ProfileData = {
  posts: PostNode[];
  postsCount: number;
  postsError?: string;
  holdings: (BalanceNode & { rank: number })[];
  holdingsCount: number;
  holdingsError?: string;
  trades: (TradeNode & { rank: number })[];
  tradesCount: number;
  tradesError?: string;
};

const TAB_NAMES = ["Posts", "Holdings", "Trades"] as const;
type TabIndex = 0 | 1 | 2;

type ProfileViewProps = {
  fetchData: () => Promise<ProfileData>;
  identifier: string;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const ProfileView = ({
  fetchData,
  identifier,
  autoRefresh = false,
  intervalSeconds = 30,
}: ProfileViewProps) => {
  const { exit } = useApp();
  const [activeTab, setActiveTab] = useState<TabIndex>(0);
  const [loading, setLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<ProfileData | null>(null);

  const { refreshCount, secondsUntilRefresh, triggerManualRefresh } =
    useAutoRefresh(intervalSeconds, autoRefresh);
  const [manualRefreshCount, setManualRefreshCount] = useState(0);
  const hasLoadedOnce = useRef(false);

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
    if (input === "1") setActiveTab(0);
    if (input === "2") setActiveTab(1);
    if (input === "3") setActiveTab(2);
    if (key.leftArrow) {
      setActiveTab((t) => (t > 0 ? ((t - 1) as TabIndex) : t));
    }
    if (key.rightArrow) {
      setActiveTab((t) =>
        t < TAB_NAMES.length - 1 ? ((t + 1) as TabIndex) : t,
      );
    }
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
          <Spinner type="dots" /> Loading profile…
        </Text>
      </Box>
    );
  }

  if (!data) return null;

  const hints: string[] = [
    "1/2/3 or \u2190 \u2192 switch tab",
    autoRefresh ? `r refresh (${secondsUntilRefresh}s)` : "r refresh",
  ];
  hints.push("q quit");
  const footer = hints.join("  \u00b7  ");

  const rankedPosts = data.posts.map((p, i) => ({ ...p, rank: i + 1 }));

  return (
    <Box flexDirection="column">
      {isRefreshing && (
        <Box paddingLeft={1}>
          <Text dimColor>
            <Spinner type="dots" /> Refreshing…
          </Text>
        </Box>
      )}

      <Box paddingLeft={1} paddingTop={1} gap={2}>
        {TAB_NAMES.map((name, i) => (
          <Text key={name} bold={activeTab === i} dimColor={activeTab !== i}>
            {activeTab === i ? `[${name}]` : name}
          </Text>
        ))}
        <Text dimColor> {identifier}</Text>
      </Box>

      {activeTab === 0 ? (
        data.postsError ? (
          <Box
            flexDirection="column"
            paddingLeft={1}
            paddingTop={1}
            paddingBottom={1}
          >
            <Text dimColor>Could not load posts: {data.postsError}</Text>
          </Box>
        ) : rankedPosts.length === 0 ? (
          <Box
            flexDirection="column"
            paddingLeft={1}
            paddingTop={1}
            paddingBottom={1}
          >
            <Text>No posts found for this profile.</Text>
          </Box>
        ) : (
          <Table
            columns={postColumns}
            data={rankedPosts}
            title="Posts"
            subtitle={`${rankedPosts.length} of ${data.postsCount}`}
          />
        )
      ) : activeTab === 1 ? (
        data.holdingsError ? (
          <Box
            flexDirection="column"
            paddingLeft={1}
            paddingTop={1}
            paddingBottom={1}
          >
            <Text dimColor>Could not load holdings: {data.holdingsError}</Text>
          </Box>
        ) : data.holdings.length === 0 ? (
          <Box
            flexDirection="column"
            paddingLeft={1}
            paddingTop={1}
            paddingBottom={1}
          >
            <Text>No holdings found for this profile.</Text>
          </Box>
        ) : (
          <Table
            columns={balanceColumns}
            data={data.holdings}
            title="Holdings"
            subtitle={`${data.holdings.length} of ${data.holdingsCount}`}
          />
        )
      ) : data.tradesError ? (
        <Box
          flexDirection="column"
          paddingLeft={1}
          paddingTop={1}
          paddingBottom={1}
        >
          <Text dimColor>Could not load trades: {data.tradesError}</Text>
        </Box>
      ) : data.trades.length === 0 ? (
        <Box
          flexDirection="column"
          paddingLeft={1}
          paddingTop={1}
          paddingBottom={1}
        >
          <Text>No trades found for this profile.</Text>
        </Box>
      ) : (
        <Table
          columns={tradeColumns}
          data={data.trades}
          title="Trades"
          subtitle={`${data.trades.length} of ${data.tradesCount}`}
        />
      )}

      <Box paddingLeft={1} paddingBottom={1}>
        <Text dimColor>{footer}</Text>
      </Box>
    </Box>
  );
};

export {
  ProfileView,
  postColumns,
  type ProfileViewProps,
  type ProfileData,
  type PostNode,
};
