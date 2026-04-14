import { useState, useEffect, useCallback } from "react";

type UseAutoRefreshReturn = {
  refreshCount: number;
  secondsUntilRefresh: number;
  triggerManualRefresh: () => void;
};

const useAutoRefresh = (
  intervalSeconds: number,
  enabled: boolean,
): UseAutoRefreshReturn => {
  const [refreshCount, setRefreshCount] = useState(0);
  const [secondsUntilRefresh, setSecondsUntilRefresh] =
    useState(intervalSeconds);
  const [resetCount, setResetCount] = useState(0);

  const triggerManualRefresh = useCallback(() => {
    setRefreshCount((c) => c + 1);
    if (enabled) {
      setSecondsUntilRefresh(intervalSeconds);
      setResetCount((c) => c + 1);
    }
  }, [enabled, intervalSeconds]);

  useEffect(() => {
    if (!enabled) return;

    setSecondsUntilRefresh(intervalSeconds);

    const ticker = setInterval(() => {
      setSecondsUntilRefresh((prev) => {
        if (prev <= 1) {
          setRefreshCount((c) => c + 1);
          return intervalSeconds;
        }
        return prev - 1;
      });
    }, 1_000);

    return () => clearInterval(ticker);
  }, [enabled, intervalSeconds, resetCount]);

  return {
    refreshCount,
    secondsUntilRefresh: enabled ? secondsUntilRefresh : 0,
    triggerManualRefresh,
  };
};

export { useAutoRefresh, type UseAutoRefreshReturn };
