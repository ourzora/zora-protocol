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
  API_KEY_BANNER,
} from "../lib/balance-columns.js";
import type {
  WalletBalance,
  WalletBalanceJson,
} from "../lib/wallet-balances.js";
import { useAutoRefresh } from "../hooks/use-auto-refresh.js";
import { copyToClipboard } from "../lib/clipboard.js";

type BalanceMode = "full" | "wallet";

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
  hasApiKey?: boolean;
};

const BalanceView = ({
  fetchData,
  sort,
  mode = "full",
  autoRefresh = false,
  intervalSeconds = 30,
  hasApiKey = false,
}: BalanceViewProps) => {
  const { exit } = useApp();
  const [loading, setLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [data, setData] = useState<BalanceData | null>(null);

  const { refreshCount, secondsUntilRefresh, triggerManualRefresh } =
    useAutoRefresh(intervalSeconds, autoRefresh);
  const hasLoadedOnce = useRef(false);
  const [selectedRow, setSelectedRow] = useState(0);
  const [copyFeedback, setCopyFeedback] = useState<string | null>(null);

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
  }, [load, refreshCount]);

  const showCoins = mode === "full";

  useEffect(() => {
    if (data && showCoins) {
      setSelectedRow((r) =>
        Math.min(r, Math.max(0, data.rankedBalances.length - 1)),
      );
    }
  }, [data, showCoins]);

  useInput((input, key) => {
    if (input === "q" || key.escape) {
      exit();
      return;
    }
    if (loading) return;

    if (showCoins && data && data.rankedBalances.length > 0) {
      if (key.upArrow || input === "k") {
        setSelectedRow((r) => Math.max(0, r - 1));
        return;
      }
      if (key.downArrow || input === "j") {
        setSelectedRow((r) => Math.min(data.rankedBalances.length - 1, r + 1));
        return;
      }
      if (input === "c" || key.return) {
        const coin = data.rankedBalances[selectedRow]?.coin;
        if (coin?.address) {
          const ok = copyToClipboard(coin.address);
          setCopyFeedback(ok ? "Copied!" : "Copy failed");
          setTimeout(() => setCopyFeedback(null), 1500);
        }
        return;
      }
    }

    if (input === "r") {
      triggerManualRefresh();
      return;
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

  const hints: string[] = [];
  if (showCoins && data.rankedBalances.length > 0) {
    hints.push("\u2191\u2193 select");
    hints.push("enter/c copy address");
  }
  hints.push(autoRefresh ? `r refresh (${secondsUntilRefresh}s)` : "r refresh");
  hints.push("q quit");
  const footer =
    hints.join("  \u00b7  ") + (copyFeedback ? `  ${copyFeedback}` : "");

  const showWallet = mode === "full" || mode === "wallet";

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
          selectedRow={selectedRow}
        />
      ) : null}
      {!hasApiKey && showCoins && data.rankedBalances.length > 0 && (
        <Box paddingLeft={1}>
          <Text dimColor>{API_KEY_BANNER}</Text>
        </Box>
      )}
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
