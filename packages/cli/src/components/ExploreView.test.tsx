import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { ExploreView } from "./ExploreView.js";

function makeCoin(overrides = {}) {
  return {
    name: "TestCoin",
    address: "0xabc123",
    coinType: "CONTENT",
    marketCap: "5000000",
    volume24h: "1234",
    marketCapDelta24h: "100000",
    ...overrides,
  };
}

describe("ExploreView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <ExploreView
        fetchCoins={() => new Promise(() => {})}
        sort="mcap"
        type="post"
        onComplete={() => {}}
        onError={() => {}}
      />,
    );
    expect(lastFrame()).toContain("Loading");
  });

  it("renders table after data loads", async () => {
    const onComplete = vi.fn();
    const { lastFrame } = render(
      <ExploreView
        fetchCoins={() => Promise.resolve([makeCoin()])}
        sort="mcap"
        type="post"
        onComplete={onComplete}
        onError={() => {}}
      />,
    );

    // Wait for state update
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestCoin");
    });
    expect(lastFrame()).toContain("$5.0M");
    expect(lastFrame()).toContain("Top by Market Cap");
    // Type column: CONTENT coinType renders as "post"
    expect(lastFrame()).toContain("post");
    expect(onComplete).toHaveBeenCalled();
  });

  it("shows empty state when no coins", async () => {
    const onComplete = vi.fn();
    const { lastFrame } = render(
      <ExploreView
        fetchCoins={() => Promise.resolve([])}
        sort="mcap"
        type="post"
        onComplete={onComplete}
        onError={() => {}}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("No coins found");
    });
    expect(onComplete).toHaveBeenCalled();
  });

  it("calls onError on fetch failure", async () => {
    const onError = vi.fn();
    render(
      <ExploreView
        fetchCoins={() => Promise.reject(new Error("Network error"))}
        sort="mcap"
        type="post"
        onComplete={() => {}}
        onError={onError}
      />,
    );

    await vi.waitFor(() => {
      expect(onError).toHaveBeenCalledWith("Network error");
    });
  });
});
