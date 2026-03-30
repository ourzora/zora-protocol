import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("@zoralabs/coins-sdk");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));
vi.mock("../lib/render.js");
vi.mock("../lib/analytics.js");

import { setApiKey, getCoin, getProfile, getTrend } from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { getCommand } from "./get.jsx";

describe("getCommand", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`exit ${code}`);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function parseJson(...args: string[]) {
    const program = createProgram(getCommand);
    return program.parseAsync(["get", ...args, "--json"], {
      from: "user",
    });
  }

  function parsedOutput(): unknown {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  it("resolves trend by ticker with positional prefix", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getTrend).mockResolvedValue({
      data: {
        trendCoin: {
          name: "Geese",
          address: "0xgeese",
          coinType: "TREND",
          marketCap: "500000",
          marketCapDelta24h: "50000",
          volume24h: "120000",
          uniqueHolders: 3200,
          createdAt: "2026-03-10T10:00:00Z",
        },
      },
    } as any);

    await parseJson("trend", "geese");

    expect(getTrend).toHaveBeenCalledWith({ ticker: "geese" });
    expect(parsedOutput()).toMatchObject({
      name: "Geese",
      address: "0xgeese",
      coinType: "trend",
      marketCap: "500000",
    });
  });

  it("exits with error when trend ticker is not found", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getTrend).mockResolvedValue({
      data: { trendCoin: null },
    } as any);

    await expect(parseJson("trend", "unknown")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No trend coin found"),
    );
  });

  it("outputs coin JSON for address lookup", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-key");
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "TestCoin",
          address: "0x1234",
          coinType: "CONTENT",
          marketCap: "5000000",
          marketCapDelta24h: "100000",
          volume24h: "250000",
          uniqueHolders: 1842,
          createdAt: "2026-03-01T14:30:00Z",
        },
      },
    } as any);

    await parseJson("0x1234");

    expect(setApiKey).toHaveBeenCalledWith("test-key");
    expect(getCoin).toHaveBeenCalledWith({ address: "0x1234" });
    expect(parsedOutput()).toMatchObject({
      name: "TestCoin",
      address: "0x1234",
      coinType: "post",
      marketCap: "5000000",
      volume24h: "250000",
      uniqueHolders: 1842,
      createdAt: "2026-03-01T14:30:00Z",
    });
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("exits with error for not-found coin", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: undefined },
    } as any);

    await expect(parseJson("0xdead")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No coin found"),
    );
  });

  it("exits with error when SDK call throws", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-key");
    vi.mocked(getCoin).mockRejectedValue(new Error("Network error"));

    await expect(parseJson("0x1234")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Network error"),
    );
  });

  it("does not call setApiKey when no key configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: { name: "NoKeyCoin", address: "0xabc", marketCap: "100" },
      },
    } as any);
    vi.mocked(setApiKey).mockClear();

    await parseJson("0xabc");

    expect(setApiKey).not.toHaveBeenCalled();
    expect(parsedOutput()).toMatchObject({ name: "NoKeyCoin" });
  });

  it("resolves creator-coin by name with positional prefix", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: { handle: "jacob", creatorCoin: { address: "0xcoin" } },
      },
    } as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "jacob",
          address: "0xcoin",
          coinType: "CREATOR",
          marketCap: "8100000",
          marketCapDelta24h: "-280000",
          volume24h: "1200000",
          uniqueHolders: 12304,
          createdAt: "2026-01-20T11:15:00Z",
        },
      },
    } as any);

    await parseJson("creator-coin", "jacob");

    expect(getProfile).toHaveBeenCalledWith({ identifier: "jacob" });
    expect(getCoin).toHaveBeenCalledWith({ address: "0xcoin" });
    expect(parsedOutput()).toMatchObject({
      name: "jacob",
      coinType: "creator-coin",
    });
  });

  it("resolves bare name when only creator-coin matches", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: { handle: "alice", creatorCoin: { address: "0xalice" } },
      },
    } as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "alice",
          address: "0xalice",
          coinType: "CREATOR",
          marketCap: "1000000",
        },
      },
    } as any);
    vi.mocked(getTrend).mockResolvedValue({
      data: { trendCoin: null },
    } as any);

    await parseJson("alice");

    expect(getProfile).toHaveBeenCalledWith({ identifier: "alice" });
    expect(getTrend).toHaveBeenCalledWith({ ticker: "alice" });
    expect(parsedOutput()).toMatchObject({ name: "alice" });
  });

  it("resolves bare name when only trend matches", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getProfile).mockResolvedValue({
      data: { profile: null },
    } as any);
    vi.mocked(getTrend).mockResolvedValue({
      data: {
        trendCoin: {
          name: "VIBES",
          address: "0xvibes",
          coinType: "TREND",
          marketCap: "300000",
          marketCapDelta24h: "10000",
          volume24h: "50000",
          uniqueHolders: 800,
          createdAt: "2026-03-15T09:00:00Z",
        },
      },
    } as any);

    await parseJson("vibes");

    expect(getTrend).toHaveBeenCalledWith({ ticker: "vibes" });
    expect(parsedOutput()).toMatchObject({
      name: "VIBES",
      coinType: "trend",
    });
  });

  it("returns both matches when bare name matches creator-coin and trend", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: { handle: "dupe", creatorCoin: { address: "0xcreator" } },
      },
    } as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "dupe",
          address: "0xcreator",
          coinType: "CREATOR",
          marketCap: "2000000",
          marketCapDelta24h: "0",
          volume24h: "0",
          uniqueHolders: 100,
        },
      },
    } as any);
    vi.mocked(getTrend).mockResolvedValue({
      data: {
        trendCoin: {
          name: "dupe",
          address: "0xtrend",
          coinType: "TREND",
          marketCap: "400000",
          marketCapDelta24h: "0",
          volume24h: "0",
          uniqueHolders: 50,
        },
      },
    } as any);

    await parseJson("dupe");

    const output = parsedOutput() as any;
    expect(output.matches).toHaveLength(2);
    expect(output.matches[0]).toMatchObject({ type: "creator-coin" });
    expect(output.matches[1]).toMatchObject({ type: "trend" });
    expect(output.hint).toContain("zora get creator-coin dupe");
    expect(output.hint).toContain("zora get trend dupe");
  });

  it("exits with error when bare name matches nothing", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getProfile).mockResolvedValue({
      data: { profile: null },
    } as any);
    vi.mocked(getTrend).mockResolvedValue({
      data: { trendCoin: null },
    } as any);

    await expect(parseJson("nonexistent")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No coin found"),
    );
  });

  it("exits with error when type prefix given without identifier", async () => {
    await expect(parseJson("creator-coin")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Missing identifier after"),
    );
    const output = parsedOutput() as any;
    expect(output.error).toContain('Missing identifier after "creator-coin"');
    expect(output.suggestion).toBeDefined();
  });
});
