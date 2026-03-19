import { describe, it, expect } from "vitest";
import { parseEther } from "viem";
import {
  formatCurrency,
  formatMcapChange,
  truncate,
  formatHolders,
  formatRelativeTime,
  formatAbsoluteTime,
  formatCreatedAt,
  formatEthDisplay,
  formatCoinsDisplay,
} from "./format.js";

describe("formatCurrency", () => {
  it("returns $0 for undefined", () => {
    expect(formatCurrency(undefined)).toBe("$0");
  });

  it("returns $0 for empty string", () => {
    expect(formatCurrency("")).toBe("$0");
  });

  it("returns $0 for zero string", () => {
    expect(formatCurrency("0")).toBe("$0");
  });

  it("formats small values", () => {
    expect(formatCurrency("1234")).toBe("$1.2K");
  });

  it("formats large values", () => {
    expect(formatCurrency("5000000")).toBe("$5.0M");
  });

  it("formats very large values", () => {
    expect(formatCurrency("2300000000")).toBe("$2.3B");
  });

  it("formats values under 1000", () => {
    expect(formatCurrency("42")).toBe("$42.0");
  });
});

describe("formatMcapChange", () => {
  it("returns dash for undefined delta", () => {
    expect(formatMcapChange("1000", undefined)).toEqual({
      text: "-",
      color: undefined,
    });
  });

  it("returns dash for undefined marketCap", () => {
    expect(formatMcapChange(undefined, "100")).toEqual({
      text: "-",
      color: undefined,
    });
  });

  it("returns dash for zero marketCap", () => {
    expect(formatMcapChange("0", "100")).toEqual({
      text: "-",
      color: undefined,
    });
  });

  it("returns dash when previous cap is zero (delta equals cap)", () => {
    expect(formatMcapChange("500", "500")).toEqual({
      text: "-",
      color: undefined,
    });
  });

  it("returns positive change with green", () => {
    const result = formatMcapChange("1100", "100");
    expect(result).toEqual({ text: "+10.0%", color: "green" });
  });

  it("returns negative change with red", () => {
    const result = formatMcapChange("900", "-100");
    expect(result).toEqual({ text: "-10.0%", color: "red" });
  });

  it("returns zero change without color", () => {
    expect(formatMcapChange("1000", "0")).toEqual({
      text: "+0.0%",
      color: undefined,
    });
  });
});

describe("formatEthDisplay", () => {
  it("formats whole ETH amounts", () => {
    expect(formatEthDisplay(parseEther("1"))).toBe("1");
  });

  it("trims trailing zeros", () => {
    expect(formatEthDisplay(parseEther("0.1"))).toBe("0.1");
  });

  it("preserves significant decimals", () => {
    expect(formatEthDisplay(parseEther("0.001"))).toBe("0.001");
  });
});

describe("formatCoinsDisplay", () => {
  it("formats with commas", () => {
    expect(formatCoinsDisplay("1234567")).toBe("1,234,567");
  });

  it("limits to 2 decimal places", () => {
    expect(formatCoinsDisplay("1234.5678")).toBe("1,234.57");
  });

  it("handles small values", () => {
    expect(formatCoinsDisplay("0.5")).toBe("0.5");
  });
});

describe("truncate", () => {
  it("returns short strings unchanged", () => {
    expect(truncate("hello", 10)).toBe("hello");
  });

  it("returns string at exact max unchanged", () => {
    expect(truncate("hello", 5)).toBe("hello");
  });

  it("truncates long strings with ellipsis", () => {
    expect(truncate("hello world", 8)).toBe("hello w\u2026");
  });
});

describe("formatHolders", () => {
  it("formats zero", () => {
    expect(formatHolders(0)).toBe("0");
  });

  it("formats with commas", () => {
    expect(formatHolders(1842)).toBe("1,842");
  });

  it("formats large number", () => {
    expect(formatHolders(12304)).toBe("12,304");
  });
});

describe("formatRelativeTime", () => {
  const now = new Date("2026-03-16T12:00:00Z");

  it("returns 'just now' for under a minute", () => {
    expect(formatRelativeTime(new Date("2026-03-16T11:59:30Z"), now)).toBe(
      "just now",
    );
  });

  it("returns minutes ago", () => {
    expect(formatRelativeTime(new Date("2026-03-16T11:45:00Z"), now)).toBe(
      "15 minutes ago",
    );
  });

  it("returns singular minute", () => {
    expect(formatRelativeTime(new Date("2026-03-16T11:59:00Z"), now)).toBe(
      "1 minute ago",
    );
  });

  it("returns hours ago", () => {
    expect(formatRelativeTime(new Date("2026-03-16T10:00:00Z"), now)).toBe(
      "2 hours ago",
    );
  });

  it("returns singular hour", () => {
    expect(formatRelativeTime(new Date("2026-03-16T11:00:00Z"), now)).toBe(
      "1 hour ago",
    );
  });

  it("returns days ago", () => {
    expect(formatRelativeTime(new Date("2026-03-13T12:00:00Z"), now)).toBe(
      "3 days ago",
    );
  });

  it("returns singular day", () => {
    expect(formatRelativeTime(new Date("2026-03-15T12:00:00Z"), now)).toBe(
      "1 day ago",
    );
  });
});

describe("formatAbsoluteTime", () => {
  it("formats afternoon time", () => {
    expect(formatAbsoluteTime(new Date(2026, 2, 1, 14, 30))).toBe(
      "2026-03-01 2:30 PM",
    );
  });

  it("formats morning time", () => {
    expect(formatAbsoluteTime(new Date(2026, 0, 20, 11, 15))).toBe(
      "2026-01-20 11:15 AM",
    );
  });

  it("formats midnight as 12 AM", () => {
    expect(formatAbsoluteTime(new Date(2026, 5, 15, 0, 5))).toBe(
      "2026-06-15 12:05 AM",
    );
  });

  it("formats noon as 12 PM", () => {
    expect(formatAbsoluteTime(new Date(2026, 5, 15, 12, 0))).toBe(
      "2026-06-15 12:00 PM",
    );
  });
});

describe("formatCreatedAt", () => {
  const now = new Date("2026-03-16T12:00:00Z");

  it("returns dash for undefined", () => {
    expect(formatCreatedAt(undefined)).toBe("-");
  });

  it("returns dash for invalid date", () => {
    expect(formatCreatedAt("not-a-date")).toBe("-");
  });

  it("returns relative + absolute", () => {
    const result = formatCreatedAt("2026-03-13T12:00:00Z", now);
    expect(result).toContain("3 days ago");
    expect(result).toMatch(/\(\d{4}-\d{2}-\d{2} \d{1,2}:\d{2} [AP]M\)/);
  });
});
