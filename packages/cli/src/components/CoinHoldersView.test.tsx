import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { CoinHoldersView } from "./CoinHoldersView.js";
import type { PageResult } from "./PaginatedTableView.js";
import type { HolderNode } from "./CoinHoldersView.js";

const makeHolder = (overrides: Partial<HolderNode> = {}): HolderNode => ({
  balance: "125000000000000000000000000",
  ownerAddress: "0xabc123def456abc123def456abc123def456abc1",
  ownerProfile: { handle: "alice" },
  ...overrides,
});

const makePage = (
  overrides?: Partial<PageResult<HolderNode>>,
): PageResult<HolderNode> => ({
  items: [makeHolder()],
  pageInfo: { hasNextPage: false },
  count: 1,
  ...overrides,
});

describe("CoinHoldersView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() => new Promise(() => {})}
        coinName="TestCoin"
        totalSupplyNum={1000000000}
        limit={10}
      />,
    );
    expect(lastFrame()).toContain("Loading holders");
  });

  it("renders table with holder data", async () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() => Promise.resolve(makePage())}
        coinName="TestCoin"
        totalSupplyNum={1000000000}
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("alice");
    });
    expect(lastFrame()).toContain("Top holders");
    expect(lastFrame()).toContain("TestCoin");
    expect(lastFrame()).toContain("Page 1");
    expect(lastFrame()).toContain("12.5%");
  });

  it("shows empty state when no holders", async () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() => Promise.resolve(makePage({ items: [], count: 0 }))}
        coinName="TestCoin"
        totalSupplyNum={1000000000}
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("No holders found");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows error state on fetch failure", async () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() => Promise.reject(new Error("Network error"))}
        coinName="TestCoin"
        totalSupplyNum={1000000000}
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: Network error");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("falls back to address when no profile handle", async () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() =>
          Promise.resolve(
            makePage({
              items: [makeHolder({ ownerProfile: undefined })],
            }),
          )
        }
        coinName="TestCoin"
        totalSupplyNum={1000000000}
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("0xabc1");
    });
  });

  it("shows dash for % Supply when totalSupply is zero", async () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() => Promise.resolve(makePage())}
        coinName="TestCoin"
        totalSupplyNum={0}
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("alice");
    });
    expect(lastFrame()).toContain("-");
  });

  it("shows <0.01% for very small balances", async () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() =>
          Promise.resolve(
            makePage({
              items: [makeHolder({ balance: "1" })],
            }),
          )
        }
        coinName="TestCoin"
        totalSupplyNum={1000000000}
        limit={10}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("<0.01%");
    });
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <CoinHoldersView
        fetchPage={() => Promise.resolve(makePage())}
        coinName="TestCoin"
        totalSupplyNum={1000000000}
        limit={10}
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("alice");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
  });
});
