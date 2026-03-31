import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("@zoralabs/coins-sdk");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));
vi.mock("../lib/render.js");

import {
  setApiKey,
  getCoin,
  getProfile,
  getTrend,
  apiGet,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { priceHistoryCommand } from "./price-history.jsx";

const makePricePoints = (prices: [string, string][]) =>
  prices.map(([timestamp, closePrice]) => ({ timestamp, closePrice }));

const makePriceHistoryResponse = (
  field: string,
  points: { timestamp: string; closePrice: string }[],
) => ({
  data: {
    zora20Token: {
      oneHour: [],
      oneDay: [],
      oneWeek: [],
      oneMonth: [],
      all: [],
      [field]: points,
    },
  },
});

const makeCoinResponse = (name: string, address: string) => ({
  data: {
    zora20Token: {
      name,
      address,
      coinType: "CONTENT",
      marketCap: "5000000",
      marketCapDelta24h: "100000",
      volume24h: "250000",
      uniqueHolders: 1000,
      createdAt: "2026-01-01T00:00:00Z",
    },
  },
});

describe("priceHistoryCommand", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(console, "error").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`exit ${code}`);
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  const parseJson = (...args: string[]) => {
    const program = createProgram(priceHistoryCommand);
    return program.parseAsync(["price-history", ...args, "--json"], {
      from: "user",
    });
  };

  const parsedOutput = (): unknown =>
    JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));

  it("exits with error for invalid --interval", async () => {
    await expect(parseJson("0x1234", "--interval", "banana")).rejects.toThrow(
      "exit 1",
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --interval"),
    );
  });

  it("exits with error when coin not found", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: undefined },
    } as any);

    await expect(parseJson("0xdead")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No coin found"),
    );
  });

  it("exits with banned message when coin is platformBlocked", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "BannedCoin",
          address: "0xbanned",
          coinType: "CONTENT",
          platformBlocked: true,
          marketCap: "100",
        },
      },
    } as any);

    await expect(parseJson("0xbanned")).rejects.toThrow("exit 1");
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(
        "The coin at 0xbanned is unavailable because it violates the Zora terms of service",
      ),
    );
  });

  it("exits with error when no price data in interval", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("TestCoin", "0x1234") as any,
    );
    vi.mocked(apiGet).mockResolvedValue({
      data: {
        zora20Token: {
          oneHour: [],
          oneDay: [],
          oneWeek: [],
          oneMonth: [],
          all: [],
        },
      },
    } as any);

    await expect(parseJson("0x1234", "--interval", "1h")).rejects.toThrow(
      "exit 1",
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("No price data found"),
    );
  });

  it("outputs price history JSON from coinPriceHistory API", async () => {
    vi.mocked(getApiKey).mockReturnValue("test-key");
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("TestCoin", "0x1234") as any,
    );

    const points = makePricePoints([
      ["2026-02-25T14:00:00Z", "0.0018"],
      ["2026-02-25T15:00:00Z", "0.0030"],
      ["2026-02-25T16:00:00Z", "0.0042"],
    ]);

    vi.mocked(apiGet).mockResolvedValue(
      makePriceHistoryResponse("oneDay", points) as any,
    );

    await parseJson("0x1234", "--interval", "24h");

    expect(setApiKey).toHaveBeenCalledWith("test-key");
    expect(apiGet).toHaveBeenCalledWith("/coinPriceHistory", {
      address: "0x1234",
    });

    const output = parsedOutput() as any;
    expect(output.coin).toBe("TestCoin");
    expect(output.type).toBe("post");
    expect(output.interval).toBe("24h");
    expect(output.high).toBe(0.0042);
    expect(output.low).toBe(0.0018);
    expect(output.prices).toHaveLength(3);
    expect(output.prices[0].price).toBe(0.0018);
    expect(output.prices[2].price).toBe(0.0042);
    // Change = (0.0042 - 0.0018) / 0.0018
    expect(output.change).toBeCloseTo(1.333, 2);
  });

  it("resolves trend coin by ticker", async () => {
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

    const points = makePricePoints([["2026-03-10T10:00:00Z", "0.005"]]);

    vi.mocked(apiGet).mockResolvedValue(
      makePriceHistoryResponse("oneWeek", points) as any,
    );

    await parseJson("trend", "geese", "--interval", "1w");

    expect(getTrend).toHaveBeenCalledWith({ ticker: "geese" });
    const output = parsedOutput() as any;
    expect(output.coin).toBe("Geese");
    expect(output.type).toBe("trend");
  });

  it("does not call setApiKey when no key configured", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("NoCoin", "0xabc") as any,
    );
    vi.mocked(setApiKey).mockClear();

    const points = makePricePoints([["2026-03-10T10:00:00Z", "0.01"]]);
    vi.mocked(apiGet).mockResolvedValue(
      makePriceHistoryResponse("oneWeek", points) as any,
    );

    await parseJson("0xabc");

    expect(setApiKey).not.toHaveBeenCalled();
  });

  it("uses ALL interval correctly", async () => {
    vi.mocked(getApiKey).mockReturnValue(undefined as any);
    vi.mocked(getCoin).mockResolvedValue(
      makeCoinResponse("AllCoin", "0xall") as any,
    );

    const points = makePricePoints([
      ["2025-01-01T00:00:00Z", "0.001"],
      ["2026-03-01T00:00:00Z", "0.010"],
    ]);

    vi.mocked(apiGet).mockResolvedValue(
      makePriceHistoryResponse("all", points) as any,
    );

    await parseJson("0xall", "--interval", "ALL");

    const output = parsedOutput() as any;
    expect(output.interval).toBe("ALL");
    expect(output.prices).toHaveLength(2);
  });
});
