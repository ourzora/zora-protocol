import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  formatCompactCurrency,
  formatChange,
  QUERY_MAP,
} from "./explore.jsx";
import { createProgram } from "../test/create-program.js";

vi.mock("@zoralabs/coins-sdk", () => ({
  setApiKey: vi.fn(),
  getCoinsMostValuable: vi.fn(),
  getMostValuableCreatorCoins: vi.fn(),
  getMostValuableAll: vi.fn(),
  getMostValuableTrends: vi.fn(),
  getExploreTopVolumeAll24h: vi.fn(),
  getExploreTopVolumeCreators24h: vi.fn(),
  getCoinsTopVolume24h: vi.fn(),
  getTopVolumeTrends24h: vi.fn(),
  getExploreNewAll: vi.fn(),
  getNewTrends: vi.fn(),
  getCreatorCoins: vi.fn(),
  getCoinsNew: vi.fn(),
  getCoinsTopGainers: vi.fn(),
  getCoinsLastTraded: vi.fn(),
  getCoinsLastTradedUnique: vi.fn(),
  getTrendingAll: vi.fn(),
  getTrendingCreators: vi.fn(),
  getTrendingPosts: vi.fn(),
  getTrendingTrends: vi.fn(),
  getExploreFeaturedCreators: vi.fn(),
  getExploreFeaturedVideos: vi.fn(),
}));

vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));

vi.mock("../lib/render.js", () => ({
  renderOnce: vi.fn(),
}));

describe("formatCompactCurrency", () => {
  it("returns $0 for undefined", () => {
    expect(formatCompactCurrency(undefined)).toBe("$0");
  });

  it("formats large numbers with compact notation", () => {
    expect(formatCompactCurrency("5000000")).toBe("$5M");
  });

  it("formats small numbers", () => {
    expect(formatCompactCurrency("100")).toMatch(/^\$100/);
  });
});

describe("formatChange", () => {
  it("returns dash for undefined delta", () => {
    expect(formatChange("1000", undefined)).toBe("-");
  });

  it("returns dash for undefined marketCap", () => {
    expect(formatChange(undefined, "100")).toBe("-");
  });

  it("returns dash for zero marketCap", () => {
    expect(formatChange("0", "100")).toBe("-");
  });

  it("returns dash when previous cap is zero (delta equals cap)", () => {
    expect(formatChange("500", "500")).toBe("-");
  });

  it("formats positive change", () => {
    expect(formatChange("1100", "100")).toBe("+10.0%");
  });

  it("formats negative change", () => {
    expect(formatChange("900", "-100")).toBe("-10.0%");
  });

  it("formats zero change", () => {
    expect(formatChange("1000", "0")).toBe("+0.0%");
  });
});

describe("QUERY_MAP", () => {
  it("mcap supports all, trend, creator-coin, post", () => {
    expect(QUERY_MAP.mcap.all).toBeDefined();
    expect(QUERY_MAP.mcap.trend).toBeDefined();
    expect(QUERY_MAP.mcap["creator-coin"]).toBeDefined();
    expect(QUERY_MAP.mcap.post).toBeDefined();
  });

  it("volume supports all, trend, creator-coin, post", () => {
    expect(QUERY_MAP.volume.all).toBeDefined();
    expect(QUERY_MAP.volume.trend).toBeDefined();
    expect(QUERY_MAP.volume["creator-coin"]).toBeDefined();
    expect(QUERY_MAP.volume.post).toBeDefined();
  });

  it("new supports all, trend, creator-coin, post", () => {
    expect(QUERY_MAP.new.all).toBeDefined();
    expect(QUERY_MAP.new.trend).toBeDefined();
    expect(QUERY_MAP.new["creator-coin"]).toBeDefined();
    expect(QUERY_MAP.new.post).toBeDefined();
  });

  it("gainers supports only post", () => {
    expect(QUERY_MAP.gainers.post).toBeDefined();
    expect(QUERY_MAP.gainers.all).toBeUndefined();
    expect(QUERY_MAP.gainers["creator-coin"]).toBeUndefined();
    expect(QUERY_MAP.gainers.trend).toBeUndefined();
  });

  it("last-traded supports only post", () => {
    expect(QUERY_MAP["last-traded"].post).toBeDefined();
    expect(QUERY_MAP["last-traded"].all).toBeUndefined();
  });

  it("last-traded-unique supports only post", () => {
    expect(QUERY_MAP["last-traded-unique"].post).toBeDefined();
    expect(QUERY_MAP["last-traded-unique"].all).toBeUndefined();
  });

  it("trending supports all, trend, creator-coin, post", () => {
    expect(QUERY_MAP.trending.all).toBeDefined();
    expect(QUERY_MAP.trending.trend).toBeDefined();
    expect(QUERY_MAP.trending["creator-coin"]).toBeDefined();
    expect(QUERY_MAP.trending.post).toBeDefined();
  });

  it("featured supports creator-coin and post", () => {
    expect(QUERY_MAP.featured["creator-coin"]).toBeDefined();
    expect(QUERY_MAP.featured.post).toBeDefined();
    expect(QUERY_MAP.featured.all).toBeUndefined();
    expect(QUERY_MAP.featured.trend).toBeUndefined();
  });
});

describe("exploreCommand action", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation((code) => { throw new Error(`exit ${code}`); });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("exits with error for invalid --sort", async () => {
    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--sort", "invalid"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Invalid --sort"));
  });

  it("exits with error for unsupported --type for given --sort", async () => {
    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--sort", "gainers", "--type", "all"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Invalid --type"));
  });

  it("exits with error for invalid --limit", async () => {
    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--limit", "abc"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Invalid --limit"));
  });

  it("exits with error for --limit above 20", async () => {
    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--limit", "25"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Invalid --limit"));
  });

  it("works without an API key", async () => {
    const { getApiKey } = await import("../lib/config.js");
    const { setApiKey, getCoinsMostValuable } = await import("@zoralabs/coins-sdk");

    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoinsMostValuable).mockResolvedValue({
      data: { exploreList: { edges: [] } },
    });

    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore"], { from: "user" });

    expect(setApiKey).not.toHaveBeenCalled();
    expect(getCoinsMostValuable).toHaveBeenCalledWith({ count: 10 });
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("outputs JSON for --json", async () => {
    const { getApiKey } = await import("../lib/config.js");
    const { getCoinsMostValuable } = await import("@zoralabs/coins-sdk");

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getCoinsMostValuable).mockResolvedValue({
      data: {
        exploreList: {
          edges: [
            {
              node: {
                name: "TestCoin",
                address: "0x1234",
                marketCap: "5000000",
              },
            },
          ],
        },
      },
    });

    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--json"], { from: "user" });

    expect(getCoinsMostValuable).toHaveBeenCalledWith({ count: 10 });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("TestCoin");
    expect(output).toContain("0x1234");
    expect(exitSpy).not.toHaveBeenCalled();
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("renders table for default output (table mode)", async () => {
    const { getApiKey } = await import("../lib/config.js");
    const { getCoinsMostValuable, setApiKey } = await import("@zoralabs/coins-sdk");
    const { renderOnce } = await import("../lib/render.js");

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getCoinsMostValuable).mockResolvedValue({
      data: {
        exploreList: {
          edges: [
            {
              node: {
                name: "TestCoin",
                address: "0x1234567890abcdef1234567890abcdef12345678",
                coinType: "CONTENT",
                marketCap: "5000000",
                volume24h: "1234",
                marketCapDelta24h: "100000",
              },
            },
          ],
        },
      },
    });

    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore"], { from: "user" });

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(renderOnce).toHaveBeenCalled();
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("fetches trending posts", async () => {
    const { getApiKey } = await import("../lib/config.js");
    const { getTrendingPosts, setApiKey } = await import("@zoralabs/coins-sdk");

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getTrendingPosts).mockResolvedValue({
      data: {
        exploreList: {
          edges: [
            {
              node: {
                name: "TrendCoin",
                address: "0xtrend",
                coinType: "CONTENT",
                marketCap: "200000",
                volume24h: "5000",
                marketCapDelta24h: "50000",
              },
            },
          ],
        },
      },
    });

    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--sort", "trending", "--type", "post", "--json"], { from: "user" });

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(getTrendingPosts).toHaveBeenCalledWith({ count: 10 });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("TrendCoin");
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("fetches top gainers", async () => {
    const { getApiKey } = await import("../lib/config.js");
    const { getCoinsTopGainers, setApiKey } = await import("@zoralabs/coins-sdk");

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getCoinsTopGainers).mockResolvedValue({
      data: {
        exploreList: {
          edges: [
            {
              node: {
                name: "GainerCoin",
                address: "0xgainer",
                coinType: "CONTENT",
                marketCap: "300000",
                volume24h: "8000",
                marketCapDelta24h: "150000",
              },
            },
          ],
        },
      },
    });

    const { exploreCommand } = await import("./explore.jsx");
    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--sort", "gainers", "--json"], { from: "user" });

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(getCoinsTopGainers).toHaveBeenCalledWith({ count: 10 });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("GainerCoin");
    expect(exitSpy).not.toHaveBeenCalled();
  });
});
