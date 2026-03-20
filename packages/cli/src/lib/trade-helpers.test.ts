import { describe, it, expect } from "vitest";
import { parseEther } from "viem";
import { formatAmountDisplay } from "./trade-helpers.js";

describe("formatAmountDisplay", () => {
  it("returns '0' for zero amount", () => {
    expect(formatAmountDisplay(0n, 18)).toBe("0");
  });

  it("formats whole ETH amounts with no unnecessary decimals", () => {
    expect(formatAmountDisplay(parseEther("10"), 18)).toBe("10");
  });

  it("truncates normal amounts to 2 decimal places", () => {
    expect(formatAmountDisplay(parseEther("1.23456"), 18)).toBe("1.23");
  });

  it("preserves 2-decimal amounts that are already visible", () => {
    expect(formatAmountDisplay(parseEther("0.05"), 18)).toBe("0.05");
  });

  it("expands decimals for amounts under 0.01 ETH", () => {
    expect(formatAmountDisplay(parseEther("0.001234"), 18)).toBe("0.001234");
  });

  it("handles amounts under 0.000001 ETH", () => {
    // 0.0000001 ETH = 100000000000n wei
    expect(formatAmountDisplay(100000000000n, 18)).toBe("0.0000001");
  });

  it("shows 4 significant digits for very small amounts", () => {
    // 0.00001234 ETH
    expect(formatAmountDisplay(parseEther("0.00001234"), 18)).toBe(
      "0.00001234",
    );
  });

  it("handles 1 wei", () => {
    const result = formatAmountDisplay(1n, 18);
    expect(result).not.toBe("0");
    expect(Number(result)).toBeGreaterThan(0);
  });

  it("formats large amounts with comma separators", () => {
    expect(formatAmountDisplay(parseEther("1234.56"), 18)).toBe("1,234.56");
  });

  it("works with non-18 decimal tokens", () => {
    // 6 decimals (USDC-like): 1.23 = 1230000n
    expect(formatAmountDisplay(1230000n, 6)).toBe("1.23");
  });
});
