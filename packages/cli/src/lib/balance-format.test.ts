import { describe, it, expect, vi } from "vitest";
import {
  computeBalanceUsdValue,
  formatBalance,
  formatBalanceAsUsd,
  normalizeTokenAmount,
  parseRawBalance,
} from "./balance-format.js";

describe("parseRawBalance", () => {
  it("converts 1e18 to 1", () => {
    expect(parseRawBalance("1000000000000000000")).toBe(1);
  });

  it("converts 0.5e18 to 0.5", () => {
    expect(parseRawBalance("500000000000000000")).toBe(0.5);
  });

  it("converts zero", () => {
    expect(parseRawBalance("0")).toBe(0);
  });

  it("handles values beyond Number.MAX_SAFE_INTEGER", () => {
    const raw = "3944403815517124397199482";
    expect(parseRawBalance(raw)).toBeCloseTo(3944403.8155, 3);
  });

  it("preserves precision for values just above MAX_SAFE_INTEGER", () => {
    expect(parseRawBalance("10000000000000000000000")).toBe(10000);
  });
});

describe("formatBalance", () => {
  it("returns 0 for zero balance", () => {
    expect(formatBalance("0")).toBe("0");
  });

  it("returns <0.001 for sub-0.001 balances", () => {
    expect(formatBalance("100000000000000")).toBe("<0.001");
  });

  it("formats small balances with fixed decimals", () => {
    expect(formatBalance("125000000000000000")).toBe("0.1250");
  });

  it("formats balances between 1 and 1000", () => {
    expect(formatBalance("50000000000000000000")).toMatch(/50/);
  });

  it("uses compact short notation for large balances", () => {
    expect(formatBalance("20000000000000000000000000")).toMatch(/20M/);
  });
});

describe("formatBalanceAsUsd", () => {
  it("returns dash when price is undefined", () => {
    expect(formatBalanceAsUsd("2000000000000000000", undefined)).toBe("-");
  });

  it("returns <$0.01 for tiny values", () => {
    expect(formatBalanceAsUsd("1000000000000000", "0.5")).toBe("<$0.01");
  });

  it("formats with 2 decimal places", () => {
    expect(formatBalanceAsUsd("4000000000000000000", "0.05")).toBe("$0.20");
  });

  it("computes correctly for large balances", () => {
    expect(formatBalanceAsUsd("10000000000000000000000", "2")).toBe(
      "$20,000.00",
    );
  });
});

describe("computeBalanceUsdValue", () => {
  it("prefers marketValueUsd when provided", () => {
    expect(
      computeBalanceUsdValue("1000000000000000000", "42.123456", "10"),
    ).toBe(42.123456);
  });

  it("falls back to balance * priceInUsdc when no marketValueUsd", () => {
    // 2 tokens at $5 each = $10
    expect(computeBalanceUsdValue("2000000000000000000", undefined, "5")).toBe(
      10,
    );
  });

  it("returns null when neither valuation nor price is available", () => {
    expect(
      computeBalanceUsdValue("1000000000000000000", undefined, undefined),
    ).toBeNull();
  });

  it("returns null for non-numeric marketValueUsd", () => {
    expect(
      computeBalanceUsdValue("1000000000000000000", "not-a-number", undefined),
    ).toBeNull();
  });

  it("returns null for non-numeric priceInUsdc", () => {
    expect(
      computeBalanceUsdValue("1000000000000000000", undefined, "bad"),
    ).toBeNull();
  });

  it("treats empty marketValueUsd as missing and falls back to price", () => {
    expect(computeBalanceUsdValue("1000000000000000000", "", "5")).toBe(5);
  });

  it("returns null for Infinity marketValueUsd", () => {
    expect(
      computeBalanceUsdValue("1000000000000000000", "Infinity", undefined),
    ).toBeNull();
  });

  it("rounds marketValueUsd to 6 decimal places", () => {
    expect(
      computeBalanceUsdValue("1000000000000000000", "1.123456789", undefined),
    ).toBe(1.123457);
  });

  it("rounds computed fallback to 6 decimal places", () => {
    expect(
      computeBalanceUsdValue("1000000000000000000", undefined, "0.1234567891"),
    ).toBe(0.123457);
  });

  it("handles zero marketValueUsd", () => {
    expect(computeBalanceUsdValue("1000000000000000000", "0", "5")).toBe(0);
  });

  it("handles zero balance with price", () => {
    expect(computeBalanceUsdValue("0", undefined, "5")).toBe(0);
  });

  it("produces consistent precision between valuation and fallback paths", () => {
    // Both paths should round to 6 decimals
    const fromValuation = computeBalanceUsdValue("0", "1.1234565", undefined);
    const fromFallback = computeBalanceUsdValue(
      "1000000000000000000",
      undefined,
      "1.1234565",
    );
    // Both should have at most 6 decimal places
    expect(
      String(fromValuation).split(".")[1]?.length ?? 0,
    ).toBeLessThanOrEqual(6);
    expect(String(fromFallback).split(".")[1]?.length ?? 0).toBeLessThanOrEqual(
      6,
    );
  });
});

describe("normalizeTokenAmount", () => {
  it("normalizes without precision loss", () => {
    expect(normalizeTokenAmount("3944403815517124397199482")).toBe(
      "3944403.815517124397199482",
    );
  });

  it("returns whole number without decimals", () => {
    expect(normalizeTokenAmount("1000000000000000000")).toBe("1");
  });

  it("handles zero", () => {
    expect(normalizeTokenAmount("0")).toBe("0");
  });

  it("respects custom decimals", () => {
    expect(normalizeTokenAmount("1500000", 6)).toBe("1.5");
  });

  it("warns and returns raw string for non-bigint input", () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    expect(normalizeTokenAmount("not-a-number")).toBe("not-a-number");
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("could not parse token amount"),
    );
    warnSpy.mockRestore();
  });
});
