import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { ProfileHoldingsView } from "./ProfileHoldingsView.js";
import type { PageResult } from "./PaginatedTableView.js";
import type { BalanceNode } from "../lib/balance-columns.js";

const makeHolding = (overrides = {}) => ({
  balance: "1000000000000000000",
  coin: {
    name: "TestCoin",
    symbol: "TEST",
    address: "0xabc123def456abc123def456abc123def456abc1",
    coinType: "CONTENT",
    marketCap: "5000000",
    marketCapDelta24h: "100000",
    tokenPrice: { priceInUsdc: "0.5" },
    ...((overrides as any).coin ?? {}),
  },
  ...overrides,
});

const makePage = (
  overrides?: Partial<PageResult<BalanceNode>>,
): PageResult<BalanceNode> => ({
  items: [makeHolding()],
  pageInfo: { hasNextPage: false },
  count: 1,
  ...overrides,
});

describe("ProfileHoldingsView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <ProfileHoldingsView
        fetchPage={() => new Promise(() => {})}
        identifier="testuser"
        limit={20}
      />,
    );
    expect(lastFrame()).toContain("Loading holdings");
  });

  it("renders table after data loads", async () => {
    const { lastFrame } = render(
      <ProfileHoldingsView
        fetchPage={() => Promise.resolve(makePage())}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("Holdings");
    expect(lastFrame()).toContain("testuser");
    expect(lastFrame()).toContain("Page 1");
    expect(lastFrame()).toContain("1 of 1");
  });

  it("shows empty state when no holdings", async () => {
    const { lastFrame } = render(
      <ProfileHoldingsView
        fetchPage={() => Promise.resolve(makePage({ items: [], count: 0 }))}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("No holdings found");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows error state on fetch failure", async () => {
    const { lastFrame } = render(
      <ProfileHoldingsView
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

  it("shows next hint when next page is available", async () => {
    const { lastFrame } = render(
      <ProfileHoldingsView
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
          items: [makeHolding({ coin: { name: "Page1Coin" } })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makeHolding({ coin: { name: "Page2Coin" } })],
          pageInfo: { hasNextPage: false },
          count: 2,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfileHoldingsView
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

  it("navigates back on p key", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [makeHolding({ coin: { name: "Page1Coin" } })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makeHolding({ coin: { name: "Page2Coin" } })],
          pageInfo: { hasNextPage: false },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makeHolding({ coin: { name: "Page1Coin" } })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfileHoldingsView
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

    stdin.write("p");
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page 1");
    });
  });

  it("shows prev hint after navigating forward", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [makeHolding({ coin: { name: "Page1Coin" } })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makeHolding({ coin: { name: "Page2Coin" } })],
          pageInfo: { hasNextPage: false },
          count: 2,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfileHoldingsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={1}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page1Coin");
    });
    expect(lastFrame()).not.toContain("prev");

    stdin.write("n");
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page2Coin");
    });
    expect(lastFrame()).toContain("prev");
  });

  it("numbers ranks across pages", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [
            makeHolding({ coin: { name: "Coin1" } }),
            makeHolding({ coin: { name: "Coin2" } }),
          ],
          pageInfo: { endCursor: "c2", hasNextPage: true },
          count: 3,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makeHolding({ coin: { name: "Coin3" } })],
          pageInfo: { hasNextPage: false },
          count: 3,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfileHoldingsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={2}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Coin1");
    });

    stdin.write("n");
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Coin3");
    });
    // Rank on page 2 with limit=2 starts at 3
    expect(lastFrame()).toContain("3");
  });

  it("refreshes on r key press", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({ items: [makeHolding({ coin: { name: "OldCoin" } })] }),
      )
      .mockResolvedValueOnce(
        makePage({ items: [makeHolding({ coin: { name: "FreshCoin" } })] }),
      );

    const { lastFrame, stdin } = render(
      <ProfileHoldingsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("OldCoin");
    });

    stdin.write("r");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("FreshCoin");
    });
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <ProfileHoldingsView
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

  it("does not show countdown when autoRefresh is false", async () => {
    const { lastFrame } = render(
      <ProfileHoldingsView
        fetchPage={() => Promise.resolve(makePage())}
        identifier="testuser"
        limit={20}
        autoRefresh={false}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("r refresh");
    expect(lastFrame()).not.toMatch(/r refresh \(\d+s\)/);
  });
});
