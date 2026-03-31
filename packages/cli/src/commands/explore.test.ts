import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { QUERY_MAP, exploreCommand } from "./explore.jsx";
import { createProgram } from "../test/create-program.js";
import {
  getCoinsMostValuable,
  getMostValuableCreatorCoins,
  getTrendingPosts,
  setApiKey,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { renderLive } from "../lib/render.js";

vi.mock("@zoralabs/coins-sdk");

vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));

vi.mock("../lib/render.js", () => ({
  renderOnce: vi.fn(),
  renderLive: vi.fn().mockResolvedValue(undefined),
}));

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
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`exit ${code}`);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("exits with error for invalid --sort", async () => {
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--sort", "invalid"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --sort"),
    );
  });

  it("exits with error for unsupported --type for given --sort", async () => {
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--sort", "featured", "--type", "all"], {
        from: "user",
      }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --type"),
    );
  });

  it("exits with error for invalid --limit", async () => {
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--limit", "abc"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --limit"),
    );
  });

  it("exits with error for --limit above 20", async () => {
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--limit", "25"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --limit"),
    );
  });

  it("works without an API key", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore"], { from: "user" });

    expect(setApiKey).not.toHaveBeenCalled();
    expect(renderLive).toHaveBeenCalled();
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("outputs JSON for --json", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getMostValuableCreatorCoins).mockResolvedValue({
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

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--json"], { from: "user" });

    expect(getMostValuableCreatorCoins).toHaveBeenCalledWith({
      count: 10,
      after: undefined,
    });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    expect(parsed.coins).toHaveLength(1);
    expect(parsed.coins[0].name).toBe("TestCoin");
    expect(parsed.coins[0].address).toBe("0x1234");
    expect(parsed.pageInfo).toBeNull();
    expect(exitSpy).not.toHaveBeenCalled();
    expect(errorSpy).not.toHaveBeenCalled();
  });

  it("renders interactive table for default output", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-api-key");

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore"], { from: "user" });

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(renderLive).toHaveBeenCalled();
    const element = vi.mocked(renderLive).mock.calls[0][0] as any;
    expect(element.props.sort).toBe("mcap");
    expect(element.props.type).toBe("creator-coin");
    expect(element.props.limit).toBe(10);
    expect(element.props.initialCursor).toBeUndefined();
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("passes initialCursor when --after is used", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--after", "some_cursor"], {
      from: "user",
    });

    expect(renderLive).toHaveBeenCalled();
    const element = vi.mocked(renderLive).mock.calls[0][0] as any;
    expect(element.props.initialCursor).toBe("some_cursor");
  });

  it("fetches trending posts", async () => {
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

    const program = createProgram(exploreCommand);
    await program.parseAsync(
      ["explore", "--sort", "trending", "--type", "post", "--json"],
      { from: "user" },
    );

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(getTrendingPosts).toHaveBeenCalledWith({
      count: 10,
      after: undefined,
    });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("TrendCoin");
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("passes --after cursor to SDK function in JSON mode", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getMostValuableCreatorCoins).mockResolvedValue({
      data: { exploreList: { edges: [], pageInfo: { hasNextPage: false } } },
    });

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--json", "--after", "abc123"], {
      from: "user",
    });

    expect(getMostValuableCreatorCoins).toHaveBeenCalledWith({
      count: 10,
      after: "abc123",
    });
  });

  it("includes pageInfo in JSON output", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getMostValuableCreatorCoins).mockResolvedValue({
      data: {
        exploreList: {
          edges: [
            {
              node: {
                name: "Coin1",
                address: "0x1",
                marketCap: "100",
              },
            },
          ],
          pageInfo: { endCursor: "cursor_xyz", hasNextPage: true },
        },
      },
    });

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--json"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    expect(parsed.pageInfo).toEqual({
      endCursor: "cursor_xyz",
      hasNextPage: true,
    });
    expect(parsed.coins).toHaveLength(1);
  });

  it("includes pageInfo null in JSON when not present", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getMostValuableCreatorCoins).mockResolvedValue({
      data: {
        exploreList: {
          edges: [
            {
              node: {
                name: "Coin1",
                address: "0x1",
                marketCap: "100",
              },
            },
          ],
        },
      },
    });

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--json"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    expect(parsed.pageInfo).toBeNull();
  });

  it("outputs consistent JSON shape for empty results", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getMostValuableCreatorCoins).mockResolvedValue({
      data: {
        exploreList: {
          edges: [],
          pageInfo: { hasNextPage: false },
        },
      },
    });

    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--json"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    expect(parsed.coins).toEqual([]);
    expect(parsed.pageInfo).toEqual({ hasNextPage: false });
  });

  it("exits with error when --json and --live are used together", async () => {
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--json", "--live"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("cannot be used together"),
    );
  });

  it("exits with error when --live and --static are used together", async () => {
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--live", "--static"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("cannot be used together"),
    );
  });

  it("exits with error when --json and --static are used together", async () => {
    const program = createProgram(exploreCommand);
    await expect(
      program.parseAsync(["explore", "--json", "--static"], { from: "user" }),
    ).rejects.toThrow("exit 1");

    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("cannot be used together"),
    );
  });

  it("warns when --refresh is used without --live", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getMostValuableCreatorCoins).mockResolvedValue({
      data: { exploreList: { edges: [] } },
    });

    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    const program = createProgram(exploreCommand);
    await program.parseAsync(["explore", "--static", "--refresh", "10"], {
      from: "user",
    });

    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("--refresh has no effect without --live"),
    );
  });
});
