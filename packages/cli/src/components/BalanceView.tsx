import { useState, useEffect, useCallback, useRef } from "react";
import { Box, Text, useInput, useApp } from "ink";
import Spinner from "ink-spinner";
import { Table } from "./table.js";
import {
  walletColumns,
  balanceColumns,
  type BalanceNode,
  type SortFlag,
  SORT_LABELS,
} from "../lib/balance-columns.js";
import type {
  WalletBalance,
  WalletBalanceJson,
} from "../lib/wallet-balances.js";
import { useAutoRefresh } from "../hooks/use-auto-refresh.js";

type BalanceMode = "full" | "wallet" | "coins";

type BalanceData = {
  walletBalances: WalletBalance[];
  walletBalancesJson: WalletBalanceJson[];
  rankedBalances: (BalanceNode & { rank: number })[];
  total: number;
};

type BalanceViewProps = {
  fetchData: () => Promise<BalanceData>;
  sort: SortFlag;
  mode?: BalanceMode;
  autoRefresh?: boolean;
  intervalSeconds?: number;
};

const BalanceView = ({
  fetchData,
  sort,
  mode = "full",
  autoRefresh = false,
  intervalSeconds = 30,
}: BalanceViewProps) => {
  const { exit } = useApp();
  const [loading, setLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<BalanceData | null>(null);

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
  }, [refreshCount, manualRefreshCount]);

  useInput((input, key) => {
    if (input === "q" || key.escape) {
      exit();
      return;
    }
    if (input === "r" && !loading) {
      triggerManualRefresh();
      setManualRefreshCount((c) => c + 1);
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
          <Spinner type="dots" /> Loading…
        </Text>
      </Box>
    );
  }

  if (!data) return null;

  const hints: string[] = ["r refresh"];
  if (autoRefresh) hints.push(`auto: ${secondsUntilRefresh}s`);
  hints.push("q quit");
  const footer = hints.join("  \u00b7  ");

  const showWallet = mode === "full" || mode === "wallet";
  const showCoins = mode === "full" || mode === "coins";

  return (
    <Box flexDirection="column">
      {isRefreshing && (
        <Box paddingLeft={1}>
          <Text dimColor>
            <Spinner type="dots" /> Refreshing…
          </Text>
        </Box>
      )}
      {showWallet && (
        <Table
          columns={walletColumns}
          data={data.walletBalances}
          title="Wallet"
        />
      )}
      {showCoins && data.rankedBalances.length === 0 ? (
        <Box
          flexDirection="column"
          paddingLeft={1}
          paddingTop={1}
          paddingBottom={1}
        >
          <Text>No coin balances found.</Text>
          <Box marginTop={1} flexDirection="column">
            <Text dimColor>Buy coins to see them here:</Text>
            <Text dimColor> zora buy {"<address>"} --eth 0.001</Text>
          </Box>
        </Box>
      ) : showCoins ? (
        <Table
          columns={balanceColumns}
          data={data.rankedBalances}
          title={`Coins · sorted by ${SORT_LABELS[sort]}`}
          subtitle={`${data.rankedBalances.length} of ${data.total}`}
        />
      ) : null}
      <Box paddingLeft={1} paddingBottom={1}>
        <Text dimColor>{footer}</Text>
      </Box>
    </Box>
  );
};

export {
  BalanceView,
  type BalanceViewProps,
  type BalanceData,
  type BalanceMode,
};
