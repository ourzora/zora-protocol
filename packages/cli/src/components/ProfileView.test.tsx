import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { ProfileView, type ProfileData } from "./ProfileView.js";

const makeProfileData = (overrides?: Partial<ProfileData>): ProfileData => ({
  posts: [
    {
      name: "Test Post",
      address: "0x1234567890abcdef1234567890abcdef12345678",
      coinType: "CONTENT",
      symbol: "TEST",
      marketCap: "1000000",
      volume24h: "50000",
      createdAt: new Date().toISOString(),
    },
  ],
  postsCount: 1,
  holdings: [],
  holdingsCount: 0,
  trades: [
    {
      transactionHash: "0xabc123",
      blockTimestamp: new Date().toISOString(),
      coinAmount: "1000000000000000000000",
      swapActivityType: "BUY",
      coin: {
        address: "0x1234567890abcdef1234567890abcdef12345678",
        name: "Test Trade Coin",
        symbol: "TTC",
        coinType: "CREATOR",
      },
      currencyAmountWithPrice: { amountUsd: "25.50" },
      rank: 1,
    },
  ],
  tradesCount: 1,
  ...overrides,
});

describe("ProfileView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => new Promise(() => {})}
        identifier="testuser"
      />,
    );
    expect(lastFrame()).toContain("Loading profile");
  });

  it("renders posts tab by default", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    expect(lastFrame()).toContain("Test Post");
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
    expect(lastFrame()).toContain("q quit");
  });

  it("does not show countdown when autoRefresh is false", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
        autoRefresh={false}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    expect(lastFrame()).toContain("r refresh");
    expect(lastFrame()).not.toMatch(/r refresh \(\d+s\)/);
  });

  it("switches to trades tab on key 3", async () => {
    const { lastFrame, stdin } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });

    stdin.write("3");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Trades]");
    });
    expect(lastFrame()).toContain("Test Trade Coin");
  });

  it("switches to holdings tab on key 2", async () => {
    const { lastFrame, stdin } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });

    stdin.write("2");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Holdings]");
    });
    expect(lastFrame()).toContain("No holdings found");
  });

  it("shows empty state for trades tab", async () => {
    const { lastFrame, stdin } = render(
      <ProfileView
        fetchData={() =>
          Promise.resolve(makeProfileData({ trades: [], tradesCount: 0 }))
        }
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });

    stdin.write("3");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Trades]");
    });
    expect(lastFrame()).toContain("No trades found");
  });

  it("shows section error when trades fail", async () => {
    const { lastFrame, stdin } = render(
      <ProfileView
        fetchData={() =>
          Promise.resolve(makeProfileData({ tradesError: "API timeout" }))
        }
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    // Posts tab still works
    expect(lastFrame()).toContain("Test Post");

    stdin.write("3");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Trades]");
    });
    expect(lastFrame()).toContain("Could not load trades");
    expect(lastFrame()).toContain("API timeout");
  });

  it("shows section error when posts fail", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() =>
          Promise.resolve(
            makeProfileData({
              postsError: "Server error",
              posts: [],
              postsCount: 0,
            }),
          )
        }
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    expect(lastFrame()).toContain("Could not load posts");
    expect(lastFrame()).toContain("Server error");
  });

  it("shows error state", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.reject(new Error("Network error"))}
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: Network error");
    });
    expect(lastFrame()).toContain("q to exit");
  });
});
