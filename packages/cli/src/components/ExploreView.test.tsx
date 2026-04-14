import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { ExploreView } from "./ExploreView.js";

const makeCoin = (overrides = {}) => ({
  name: "TestCoin",
  address: "0xabc123",
  coinType: "CONTENT",
  marketCap: "5000000",
  volume24h: "1234",
  marketCapDelta24h: "100000",
  ...overrides,
});

describe("ExploreView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() => new Promise(() => {})}
        sort="mcap"
        type="post"
        limit={10}
      />,
    );
    expect(lastFrame()).toContain("Loading");
  });

  it("renders table after data loads", async () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() =>
          Promise.resolve({
            items: [makeCoin()],
            pageInfo: { hasNextPage: false },
          })
        }
        sort="mcap"
        type="post"
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("$5.0M");
    expect(lastFrame()).toContain("Top by Market Cap");
    expect(lastFrame()).toContain("Page 1");
  });

  it("shows empty state when no coins", async () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() =>
          Promise.resolve({ items: [], pageInfo: { hasNextPage: false } })
        }
        sort="mcap"
        type="post"
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("No coins found");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows error state on fetch failure", async () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() => Promise.reject(new Error("Network error"))}
        sort="mcap"
        type="post"
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: Network error");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows navigation hints when next page is available", async () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() =>
          Promise.resolve({
            items: [makeCoin()],
            pageInfo: { endCursor: "cursor_abc", hasNextPage: true },
          })
        }
        sort="mcap"
        type="post"
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("next");
    });
    expect(lastFrame()).toContain("q quit");
    expect(lastFrame()).not.toContain("prev");
  });

  it("navigates to next page on n key", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Page1Coin" })],
        pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
      })
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Page2Coin" })],
        pageInfo: { hasNextPage: false },
      });

    const { lastFrame, stdin } = render(
      <ExploreView fetchPage={fetchPage} sort="mcap" type="post" limit={10} />,
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

  it("navigates back on p key using cache", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Page1Coin" })],
        pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
      })
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Page2Coin" })],
        pageInfo: { hasNextPage: false },
      });

    const { lastFrame, stdin } = render(
      <ExploreView fetchPage={fetchPage} sort="mcap" type="post" limit={10} />,
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
      expect(lastFrame()).toContain("Page1Coin");
    });
    expect(lastFrame()).toContain("Page 1");
    // Only 2 fetches: page 1 cached, no re-fetch on back
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });

  it("shows prev hint after navigating forward", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Page1Coin" })],
        pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
      })
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Page2Coin" })],
        pageInfo: { hasNextPage: false },
      });

    const { lastFrame, stdin } = render(
      <ExploreView fetchPage={fetchPage} sort="mcap" type="post" limit={10} />,
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

  it("uses initialCursor for first fetch", async () => {
    const fetchPage = vi.fn().mockResolvedValue({
      items: [makeCoin()],
      pageInfo: { hasNextPage: false },
    });

    const { lastFrame } = render(
      <ExploreView
        fetchPage={fetchPage}
        sort="mcap"
        type="post"
        limit={10}
        initialCursor="start_here"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(fetchPage).toHaveBeenCalledWith("start_here");
  });

  it("numbers ranks across pages", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Coin1" }), makeCoin({ name: "Coin2" })],
        pageInfo: { endCursor: "c2", hasNextPage: true },
      })
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "Coin3" })],
        pageInfo: { hasNextPage: false },
      });

    const { lastFrame, stdin } = render(
      <ExploreView fetchPage={fetchPage} sort="mcap" type="post" limit={2} />,
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

  it("refreshes current page on r key", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "OldData" })],
        pageInfo: { hasNextPage: false },
      })
      .mockResolvedValueOnce({
        items: [makeCoin({ name: "FreshData" })],
        pageInfo: { hasNextPage: false },
      });

    const { lastFrame, stdin } = render(
      <ExploreView fetchPage={fetchPage} sort="mcap" type="post" limit={10} />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("OldData");
    });

    stdin.write("r");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("FreshData");
    });
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });

  it("shows refresh hint in footer", async () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() =>
          Promise.resolve({
            items: [makeCoin()],
            pageInfo: { hasNextPage: false },
          })
        }
        sort="mcap"
        type="post"
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("r refresh");
  });

  it("shows auto-refresh countdown when autoRefresh is enabled", async () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() =>
          Promise.resolve({
            items: [makeCoin()],
            pageInfo: { hasNextPage: false },
          })
        }
        sort="mcap"
        type="post"
        limit={10}
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
  });

  it("does not show countdown when autoRefresh is not set", async () => {
    const { lastFrame } = render(
      <ExploreView
        fetchPage={() =>
          Promise.resolve({
            items: [makeCoin()],
            pageInfo: { hasNextPage: false },
          })
        }
        sort="mcap"
        type="post"
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("r refresh");
    expect(lastFrame()).not.toMatch(/r refresh \(\d+s\)/);
  });
});
