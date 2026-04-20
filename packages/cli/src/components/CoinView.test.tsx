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
  totalSupply: "1000000000",
  uniqueHolders: 1200,
  createdAt: "2026-01-01T00:00:00Z",
  platformBlocked: false,
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
  trades: [],
  holders: null,
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

  it("shows tab switch hint and all tab names", async () => {
    const { lastFrame } = render(
      <CoinView fetchData={() => Promise.resolve(makeCoinViewData())} />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Price History]");
    });
    expect(lastFrame()).toContain("switch tab");
    expect(lastFrame()).toContain("Trades");
    expect(lastFrame()).toContain("Holders");
  });

  it("renders trade data when switching to Trades tab", async () => {
    const trades = [
      {
        activityType: "BUY" as const,
        coinAmount: "1000000000000000000",
        blockTimestamp: "2026-04-10T12:00:00Z",
        senderAddress: "0xabcdef1234567890abcdef1234567890abcdef12",
        senderProfile: { handle: "alice" },
        currencyAmountWithPrice: { priceUsdc: "5.25" },
        transactionHash: "0xtx1",
      },
      {
        activityType: "SELL" as const,
        coinAmount: "500000000000000000",
        blockTimestamp: "2026-04-10T11:00:00Z",
        senderAddress: "0x9999000000000000000000000000000000009999",
        currencyAmountWithPrice: { priceUsdc: "2.10" },
        transactionHash: "0xtx2",
      },
    ];

    const { lastFrame, stdin } = render(
      <CoinView
        fetchData={() => Promise.resolve(makeCoinViewData({ trades }))}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Price History]");
    });

    // Switch to Trades tab
    stdin.write("2");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Trades]");
    });
    expect(lastFrame()).toContain("BUY");
    expect(lastFrame()).toContain("alice");
    expect(lastFrame()).toContain("$5.25");
  });

  it("shows empty message on Trades tab when trades is empty", async () => {
    const { lastFrame, stdin } = render(
      <CoinView
        fetchData={() => Promise.resolve(makeCoinViewData({ trades: [] }))}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Price History]");
    });

    stdin.write("2");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Trades]");
    });
    expect(lastFrame()).toContain("No trades found");
  });
});
