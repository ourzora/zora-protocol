import { describe, it, expect, vi, afterEach } from "vitest";

vi.mock("@zoralabs/coins-sdk");

import { apiGet } from "@zoralabs/coins-sdk";
import {
  formatPrice,
  formatChange,
  fetchPriceHistory,
  VALID_INTERVALS,
  INTERVAL_TO_API_FIELD,
} from "./price-history.js";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("formatPrice", () => {
  it("formats prices >= 1 with 2 decimals", () => {
    expect(formatPrice(1)).toBe("$1.00");
    expect(formatPrice(42.5)).toBe("$42.50");
    expect(formatPrice(1234.567)).toBe("$1234.57");
  });

  it("formats prices >= 0.01 with 4 decimals", () => {
    expect(formatPrice(0.01)).toBe("$0.0100");
    expect(formatPrice(0.0567)).toBe("$0.0567");
    expect(formatPrice(0.99)).toBe("$0.9900");
  });

  it("formats tiny prices with 4 significant digits", () => {
    expect(formatPrice(0.001234)).toBe("$0.001234");
    expect(formatPrice(0.00009876)).toBe("$0.00009876");
  });
});

describe("formatChange", () => {
  it("returns dash when first price is 0", () => {
    expect(formatChange(0, 100)).toEqual({ text: "-", color: undefined });
  });

  it("formats positive change in green", () => {
    const result = formatChange(100, 150);
    expect(result.text).toBe("+50.0%");
    expect(result.color).toBe("green");
  });

  it("formats negative change in red", () => {
    const result = formatChange(100, 75);
    expect(result.text).toBe("-25.0%");
    expect(result.color).toBe("red");
  });

  it("formats zero change with no color", () => {
    const result = formatChange(100, 100);
    expect(result.text).toBe("+0.0%");
    expect(result.color).toBeUndefined();
  });

  it("handles large percentage gains", () => {
    const result = formatChange(1, 100);
    expect(result.text).toBe("+9900.0%");
    expect(result.color).toBe("green");
  });
});

describe("fetchPriceHistory", () => {
  it("fetches and maps price points for given interval", async () => {
    vi.mocked(apiGet).mockResolvedValue({
      data: {
        zora20Token: {
          oneWeek: [
            { timestamp: "2026-01-01T00:00:00Z", closePrice: "0.005" },
            { timestamp: "2026-01-02T00:00:00Z", closePrice: "0.010" },
          ],
        },
      },
    } as any);

    const result = await fetchPriceHistory("0x1234", "1w");

    expect(apiGet).toHaveBeenCalledWith("/coinPriceHistory", {
      address: "0x1234",
    });
    expect(result).toEqual([
      { timestamp: "2026-01-01T00:00:00Z", price: 0.005 },
      { timestamp: "2026-01-02T00:00:00Z", price: 0.01 },
    ]);
  });

  it("returns empty array when zora20Token is null", async () => {
    vi.mocked(apiGet).mockResolvedValue({
      data: { zora20Token: null },
    } as any);

    const result = await fetchPriceHistory("0x1234", "1w");
    expect(result).toEqual([]);
  });

  it("returns empty array when data is undefined", async () => {
    vi.mocked(apiGet).mockResolvedValue({
      data: undefined,
    } as any);

    const result = await fetchPriceHistory("0x1234", "1h");
    expect(result).toEqual([]);
  });

  it("returns empty array when interval field has no points", async () => {
    vi.mocked(apiGet).mockResolvedValue({
      data: {
        zora20Token: {
          oneDay: [],
        },
      },
    } as any);

    const result = await fetchPriceHistory("0x1234", "24h");
    expect(result).toEqual([]);
  });

  it("returns empty array when interval field is undefined", async () => {
    vi.mocked(apiGet).mockResolvedValue({
      data: {
        zora20Token: {},
      },
    } as any);

    const result = await fetchPriceHistory("0x1234", "1m");
    expect(result).toEqual([]);
  });

  it("uses correct API field for each interval", async () => {
    for (const interval of VALID_INTERVALS) {
      const field = INTERVAL_TO_API_FIELD[interval];
      vi.mocked(apiGet).mockResolvedValue({
        data: {
          zora20Token: {
            [field]: [{ timestamp: "2026-01-01T00:00:00Z", closePrice: "1.0" }],
          },
        },
      } as any);

      const result = await fetchPriceHistory("0xabc", interval);
      expect(result).toHaveLength(1);
      expect(result[0].price).toBe(1.0);
    }
  });
});
