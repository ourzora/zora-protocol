import { describe, it, expect, vi } from "vitest";
import {
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
