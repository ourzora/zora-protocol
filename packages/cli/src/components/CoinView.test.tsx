import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { CoinView, type CoinViewData } from "./CoinView.js";
import type { ResolvedCoin } from "../lib/coin-ref.js";

const makeCoin = (overrides?: Partial<ResolvedCoin>): ResolvedCoin => ({
  name: "TestCoin",
  address: "0x1234567890abcdef1234567890abcdef12345678",
  coinType: "CREATOR",
  marketCap: "5000000",
  marketCapDelta24h: "100000",
  volume24h: "250000",
  uniqueHolders: 1200,
  createdAt: "2026-01-01T00:00:00Z",
  ...overrides,
});

const makeCoinViewData = (overrides?: Partial<CoinViewData>): CoinViewData => ({
  coin: makeCoin(),
  priceHistory: {
    high: "$0.0052",
    low: "$0.0041",
    change: { text: "+23.0%", color: "green" },
    sparklineText: "▁▂▃▅▇",
    interval: "1w",
  },
  ...overrides,
});

describe("CoinView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <CoinView fetchData={() => new Promise(() => {})} />,
    );
    expect(lastFrame()).toContain("Loading coin");
  });

  it("renders coin detail and price history tab", async () => {
    const { lastFrame } = render(
      <CoinView fetchData={() => Promise.resolve(makeCoinViewData())} />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("[Price History]");
    expect(lastFrame()).toContain("$0.0052");
    expect(lastFrame()).toContain("$0.0041");
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <CoinView
        fetchData={() => Promise.resolve(makeCoinViewData())}
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Price History]");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
    expect(lastFrame()).toContain("q quit");
  });

  it("does not show countdown when autoRefresh is false", async () => {
    const { lastFrame } = render(
      <CoinView
        fetchData={() => Promise.resolve(makeCoinViewData())}
        autoRefresh={false}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Price History]");
    });
    expect(lastFrame()).toContain("r refresh");
    expect(lastFrame()).not.toMatch(/r refresh \(\d+s\)/);
  });

  it("shows error state with descriptive message", async () => {
    const { lastFrame } = render(
      <CoinView
        fetchData={() => Promise.reject(new Error("No coin found at 0xdead"))}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: No coin found at 0xdead");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows no price data message when priceHistory is null", async () => {
    const { lastFrame } = render(
      <CoinView
        fetchData={() =>
          Promise.resolve(makeCoinViewData({ priceHistory: null }))
        }
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("No price data available");
  });

  it("renders immediately with initialData and does not call fetchData", async () => {
    const fetchData = vi.fn();
    const { lastFrame } = render(
      <CoinView fetchData={fetchData} initialData={makeCoinViewData()} />,
    );

    expect(lastFrame()).toContain("TestCoin");
    expect(lastFrame()).toContain("[Price History]");
    expect(lastFrame()).not.toContain("Loading");
    expect(fetchData).not.toHaveBeenCalled();
  });

  it("shows inline refresh error while keeping stale data visible", async () => {
    let callCount = 0;
    const fetchData = () => {
      callCount++;
      if (callCount === 1) return Promise.resolve(makeCoinViewData());
      return Promise.reject(new Error("Network timeout"));
    };

    const { lastFrame, stdin } = render(
      <CoinView fetchData={fetchData} autoRefresh={false} />,
    );

    // First load succeeds
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });

    // Trigger manual refresh with "r" key
    stdin.write("r");

    // Should show the error banner while still displaying the coin data
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Refresh failed: Network timeout");
    });
    expect(lastFrame()).toContain("TestCoin");
    expect(lastFrame()).toContain("[Price History]");
  });

  it("does not show tab switch hint with single tab", async () => {
    const { lastFrame } = render(
      <CoinView fetchData={() => Promise.resolve(makeCoinViewData())} />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Price History]");
    });
    expect(lastFrame()).not.toContain("switch tab");
  });
});
