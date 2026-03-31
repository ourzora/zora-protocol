import { describe, it, expect } from "vitest";
import { parseEther } from "viem";
import {
  formatCompactUsd,
  formatMcapChange,
  truncate,
  truncateAddress,
  formatHolders,
  formatRelativeTime,
  formatAbsoluteTime,
  formatCreatedAt,
  styledText,
  formatAmountDisplay,
  formatUsd,
} from "./format.js";

describe("formatCompactUsd", () => {
  it("returns $0 for undefined", () => {
    expect(formatCompactUsd(undefined)).toBe("$0");
  });

  it("returns $0 for empty string", () => {
    expect(formatCompactUsd("")).toBe("$0");
  });

  it("returns $0 for zero string", () => {
    expect(formatCompactUsd("0")).toBe("$0");
  });

  it("formats small values", () => {
    expect(formatCompactUsd("1234")).toBe("$1.2K");
  });

  it("formats large values", () => {
    expect(formatCompactUsd("5000000")).toBe("$5.0M");
  });

  it("formats very large values", () => {
    expect(formatCompactUsd("2300000000")).toBe("$2.3B");
  });

  it("formats values under 1000", () => {
    expect(formatCompactUsd("42")).toBe("$42.0");
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

describe("formatAmountDisplay", () => {
  it("returns '0' for zero amount", () => {
    expect(formatAmountDisplay(0n, 18)).toBe("0");
  });

  it("formats whole ETH amounts with no unnecessary decimals", () => {
    expect(formatAmountDisplay(parseEther("10"), 18)).toBe("10");
  });

  it("rounds normal amounts to 2 decimal places", () => {
    expect(formatAmountDisplay(parseEther("1.23456"), 18)).toBe("1.23");
    expect(formatAmountDisplay(parseEther("1234.5678"), 18)).toBe("1,234.57");
  });

  it("preserves 2-decimal amounts that are already visible", () => {
    expect(formatAmountDisplay(parseEther("0.05"), 18)).toBe("0.05");
  });

  it("expands decimals for amounts under 0.01 ETH", () => {
    expect(formatAmountDisplay(parseEther("0.001234"), 18)).toBe("0.001234");
  });

  it("handles amounts under 0.000001 ETH", () => {
    expect(formatAmountDisplay(100000000000n, 18)).toBe("0.0000001");
  });

  it("shows 4 significant digits for very small amounts", () => {
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
    expect(formatAmountDisplay(1230000n, 6)).toBe("1.23");
  });
});

describe("formatUsd", () => {
  it("formats whole dollar amounts with two decimals", () => {
    expect(formatUsd(10)).toBe("$10.00");
  });

  it("formats cents correctly", () => {
    expect(formatUsd(0.5)).toBe("$0.50");
  });

  it("rounds to two decimal places", () => {
    expect(formatUsd(1.999)).toBe("$2.00");
    expect(formatUsd(1.234)).toBe("$1.23");
  });

  it("formats large values with comma separators", () => {
    expect(formatUsd(1234.56)).toBe("$1,234.56");
    expect(formatUsd(1000000)).toBe("$1,000,000.00");
  });

  it("formats zero", () => {
    expect(formatUsd(0)).toBe("$0.00");
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

describe("styledText", () => {
  // In test environment, stdout is not a TTY, so styledText returns plain text
  it("returns plain text when not a TTY", () => {
    expect(styledText("hello", "dim")).toBe("hello");
  });

  it("returns plain text when NO_COLOR is set", () => {
    process.env.NO_COLOR = "1";
    expect(styledText("hello", "bold")).toBe("hello");
    delete process.env.NO_COLOR;
  });

  it("wraps text with ANSI codes when TTY and no NO_COLOR", () => {
    const origIsTTY = process.stdout.isTTY;
    process.stdout.isTTY = true;
    delete process.env.NO_COLOR;

    expect(styledText("hello", "dim")).toBe("\x1b[2mhello\x1b[22m");
    expect(styledText("hello", "bold")).toBe("\x1b[1mhello\x1b[22m");

    process.stdout.isTTY = origIsTTY;
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

describe("truncateAddress", () => {
  it("truncates a full address to 0xABCD…1234 format", () => {
    expect(truncateAddress("0x1234567890abcdef1234567890abcdef12345678")).toBe(
      "0x1234\u20265678",
    );
  });

  it("preserves the 0x prefix and last 4 chars", () => {
    expect(truncateAddress("0xabcdefabcdefabcdefabcdefabcdefabcdefabcd")).toBe(
      "0xabcd\u2026abcd",
    );
  });
});
