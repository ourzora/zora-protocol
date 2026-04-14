import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { BalanceView, type BalanceData } from "./BalanceView.js";

const makeBalanceData = (overrides?: Partial<BalanceData>): BalanceData => ({
  walletBalances: [
    { name: "Ethereum", symbol: "ETH", balance: "1.5", usdValue: "$3,000.00" },
  ],
  walletBalancesJson: [],
  rankedBalances: [
    {
      rank: 1,
      balance: "1000000000000000000",
      coin: {
        name: "TestCoin",
        symbol: "TEST",
        marketCap: "5000000",
        marketCapDelta24h: "100000",
        tokenPrice: { priceInUsdc: "0.5" },
      },
    },
  ],
  total: 1,
  ...overrides,
});

describe("BalanceView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <BalanceView fetchData={() => new Promise(() => {})} sort="usd-value" />,
    );
    expect(lastFrame()).toContain("Loading");
  });

  it("renders wallet and coins tables after data loads", async () => {
    const { lastFrame } = render(
      <BalanceView
        fetchData={() => Promise.resolve(makeBalanceData())}
        sort="usd-value"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Wallet");
    });
    expect(lastFrame()).toContain("ETH");
    expect(lastFrame()).toContain("TestCoin");
    expect(lastFrame()).toContain("Coins");
  });

  it("shows only wallet table in wallet mode", async () => {
    const { lastFrame } = render(
      <BalanceView
        fetchData={() => Promise.resolve(makeBalanceData())}
        sort="usd-value"
        mode="wallet"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Wallet");
    });
    expect(lastFrame()).toContain("ETH");
    expect(lastFrame()).not.toContain("Coins");
  });

  it("shows empty state when no coins", async () => {
    const { lastFrame } = render(
      <BalanceView
        fetchData={() =>
          Promise.resolve(makeBalanceData({ rankedBalances: [], total: 0 }))
        }
        sort="usd-value"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("No coin balances found");
    });
  });

  it("shows error state on fetch failure", async () => {
    const { lastFrame } = render(
      <BalanceView
        fetchData={() => Promise.reject(new Error("Network error"))}
        sort="usd-value"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: Network error");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <BalanceView
        fetchData={() => Promise.resolve(makeBalanceData())}
        sort="usd-value"
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Wallet");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
    expect(lastFrame()).toContain("q quit");
  });

  it("does not show countdown when autoRefresh is false", async () => {
    const { lastFrame } = render(
      <BalanceView
        fetchData={() => Promise.resolve(makeBalanceData())}
        sort="usd-value"
        autoRefresh={false}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Wallet");
    });
    expect(lastFrame()).toContain("r refresh");
    expect(lastFrame()).not.toMatch(/r refresh \(\d+s\)/);
  });

  it("refreshes on r key press", async () => {
    const fetchData = vi
      .fn()
      .mockResolvedValueOnce(makeBalanceData())
      .mockResolvedValueOnce(
        makeBalanceData({
          walletBalances: [
            {
              name: "Ethereum",
              symbol: "ETH",
              balance: "2.0",
              usdValue: "$4,000.00",
            },
          ],
        }),
      );

    const { lastFrame, stdin } = render(
      <BalanceView fetchData={fetchData} sort="usd-value" />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Wallet");
    });

    stdin.write("r");

    await vi.waitFor(() => {
      expect(fetchData).toHaveBeenCalledTimes(2);
    });
  });
});
