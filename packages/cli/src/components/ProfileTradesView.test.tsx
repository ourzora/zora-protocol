import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { ProfileTradesView } from "./ProfileTradesView.js";
import type { PageResult } from "./PaginatedTableView.js";
import type { TradeNode } from "./ProfileTradesView.js";

const makeTrade = (overrides = {}): TradeNode => ({
  transactionHash: "0xabc123",
  blockTimestamp: new Date().toISOString(),
  coinAmount: "1000000000000000000000",
  swapActivityType: "BUY",
  coin: {
    address: "0x1234567890abcdef1234567890abcdef12345678",
    name: "TestCoin",
    symbol: "TC",
    coinType: "CREATOR",
  },
  currencyAmountWithPrice: {
    amountUsd: "25.50",
  },
  ...overrides,
});

const makePage = (
  overrides?: Partial<PageResult<TradeNode>>,
): PageResult<TradeNode> => ({
  items: [makeTrade()],
  pageInfo: { hasNextPage: false },
  count: 1,
  ...overrides,
});

describe("ProfileTradesView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() => new Promise(() => {})}
        identifier="testuser"
        limit={20}
      />,
    );
    expect(lastFrame()).toContain("Loading trades");
  });

  it("renders table after data loads", async () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() => Promise.resolve(makePage())}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("Trades");
    expect(lastFrame()).toContain("testuser");
    expect(lastFrame()).toContain("BUY");
    expect(lastFrame()).toContain("Page 1");
    expect(lastFrame()).toContain("1 of 1");
  });

  it("shows empty state when no trades", async () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() => Promise.resolve(makePage({ items: [], count: 0 }))}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("No trades found");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows error state on fetch failure", async () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() => Promise.reject(new Error("Network error"))}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: Network error");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("displays SELL trades", async () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() =>
          Promise.resolve(
            makePage({
              items: [makeTrade({ swapActivityType: "SELL" })],
            }),
          )
        }
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("SELL");
    });
  });

  it("handles missing coin data gracefully", async () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() =>
          Promise.resolve(
            makePage({
              items: [makeTrade({ coin: undefined })],
            }),
          )
        }
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Unknown");
    });
  });

  it("shows next hint when next page is available", async () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() =>
          Promise.resolve(
            makePage({
              pageInfo: { endCursor: "cursor_abc", hasNextPage: true },
              count: 40,
            }),
          )
        }
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("next");
    expect(lastFrame()).not.toContain("prev");
  });

  it("navigates to next page on n key", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [
            makeTrade({ coin: { ...makeTrade().coin!, name: "Page1Coin" } }),
          ],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [
            makeTrade({ coin: { ...makeTrade().coin!, name: "Page2Coin" } }),
          ],
          pageInfo: { hasNextPage: false },
          count: 2,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfileTradesView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={1}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page1Coin");
    });

    stdin.write("n");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page2Coin");
    });
    expect(lastFrame()).toContain("Page 2");
    expect(fetchPage).toHaveBeenCalledWith("cursor_page2");
  });

  it("refreshes on r key press", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [
            makeTrade({ coin: { ...makeTrade().coin!, name: "OldTrade" } }),
          ],
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [
            makeTrade({ coin: { ...makeTrade().coin!, name: "FreshTrade" } }),
          ],
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfileTradesView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("OldTrade");
    });

    stdin.write("r");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("FreshTrade");
    });
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <ProfileTradesView
        fetchPage={() => Promise.resolve(makePage())}
        identifier="testuser"
        limit={20}
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
  });
});
