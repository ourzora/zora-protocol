import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render } from "ink-testing-library";
import { createElement, type FC } from "react";
import { Text } from "ink";
import { useAutoRefresh } from "./use-auto-refresh.js";

type HarnessProps = {
  intervalSeconds: number;
  enabled: boolean;
  onRefresh?: (count: number) => void;
};

const Harness: FC<HarnessProps> = ({ intervalSeconds, enabled, onRefresh }) => {
  const { refreshCount, secondsUntilRefresh } = useAutoRefresh(
    intervalSeconds,
    enabled,
  );
  onRefresh?.(refreshCount);
  return createElement(
    Text,
    null,
    `count:${refreshCount} seconds:${secondsUntilRefresh}`,
  );
};

describe("useAutoRefresh", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns zero values when disabled", () => {
    const { lastFrame } = render(
      createElement(Harness, { intervalSeconds: 30, enabled: false }),
    );
    expect(lastFrame()).toContain("count:0");
    expect(lastFrame()).toContain("seconds:0");
  });

  it("starts countdown at intervalSeconds when enabled", () => {
    const { lastFrame } = render(
      createElement(Harness, { intervalSeconds: 5, enabled: true }),
    );
    expect(lastFrame()).toContain("seconds:5");
    expect(lastFrame()).toContain("count:0");
  });

  it("increments refreshCount when countdown reaches zero", async () => {
    const onRefresh = vi.fn();
    render(
      createElement(Harness, {
        intervalSeconds: 3,
        enabled: true,
        onRefresh,
      }),
    );

    await vi.advanceTimersByTimeAsync(3_000);

    expect(onRefresh).toHaveBeenCalledWith(1);
  });

  it("increments refreshCount multiple times", async () => {
    const onRefresh = vi.fn();
    render(
      createElement(Harness, {
        intervalSeconds: 2,
        enabled: true,
        onRefresh,
      }),
    );

    await vi.advanceTimersByTimeAsync(6_000);

    expect(onRefresh).toHaveBeenCalledWith(3);
  });
});
