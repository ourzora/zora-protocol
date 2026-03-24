import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render } from "ink-testing-library";
import { Table, truncate, computeColumnWidths, type Column } from "./table.js";

interface Item {
  rank: number;
  name: string;
  value: string;
}

const COLUMNS: Column<Item>[] = [
  { header: "#", width: 5, accessor: (item) => String(item.rank) },
  { header: "Name", width: 20, accessor: (item) => item.name },
  { header: "Value", width: 10, accessor: (item) => item.value },
];

const DATA: Item[] = [
  { rank: 1, name: "Alpha", value: "$100" },
  { rank: 2, name: "Beta", value: "$200" },
];

describe("Table", () => {
  it("renders column headers", () => {
    const { lastFrame } = render(
      <Table data={DATA.slice(0, 1)} columns={COLUMNS} fullWidth={false} />,
    );
    const frame = lastFrame();
    expect(frame).toContain("#");
    expect(frame).toContain("Name");
    expect(frame).toContain("Value");
  });

  it("renders row data with correct values", () => {
    const { lastFrame } = render(
      <Table data={DATA} columns={COLUMNS} fullWidth={false} />,
    );
    const frame = lastFrame();
    expect(frame).toContain("Alpha");
    expect(frame).toContain("Beta");
    expect(frame).toContain("$100");
  });

  it("renders title when provided", () => {
    const { lastFrame } = render(
      <Table
        data={DATA.slice(0, 1)}
        columns={COLUMNS}
        title="Top Coins"
        subtitle="3 results"
        fullWidth={false}
      />,
    );
    const frame = lastFrame();
    expect(frame).toContain("Top Coins");
    expect(frame).toContain("3 results");
  });

  it("renders without title", () => {
    const { lastFrame } = render(
      <Table data={DATA.slice(0, 1)} columns={COLUMNS} fullWidth={false} />,
    );
    const frame = lastFrame();
    expect(frame).toContain("Alpha");
    expect(frame).not.toContain("Top Coins");
  });

  it("truncates long values by default", () => {
    const columns: Column<Item>[] = [
      { header: "Name", width: 8, accessor: (item) => item.name },
    ];
    const data: Item[] = [{ rank: 1, name: "VeryLongTokenName", value: "" }];
    const { lastFrame } = render(
      <Table data={data} columns={columns} fullWidth={false} />,
    );
    const frame = lastFrame()!;
    // width 8, truncate at width-2=6: "VeryL…"
    expect(frame).toContain("VeryL\u2026");
    expect(frame).not.toContain("VeryLongTokenName");
  });

  it("does not truncate when noTruncate is set", () => {
    const columns: Column<Item>[] = [
      {
        header: "Name",
        width: 8,
        noTruncate: true,
        accessor: (item) => item.name,
      },
    ];
    const data: Item[] = [{ rank: 1, name: "VeryLongTokenName", value: "" }];
    const { lastFrame } = render(
      <Table data={data} columns={columns} fullWidth={false} />,
    );
    const frame = lastFrame()!;
    // With noTruncate, the ellipsis character should not appear (Ink wraps instead)
    expect(frame).not.toContain("\u2026");
  });

  describe("truncate", () => {
    it("returns string unchanged when within max length", () => {
      expect(truncate("hello", 10)).toBe("hello");
    });

    it("truncates and adds ellipsis when string exceeds max", () => {
      expect(truncate("VeryLongTokenName", 6)).toBe("VeryL\u2026");
    });

    it("handles exact boundary length", () => {
      expect(truncate("abcde", 5)).toBe("abcde");
    });
  });

  describe("computeColumnWidths", () => {
    let originalColumns: number | undefined;

    beforeEach(() => {
      originalColumns = process.stdout.columns;
    });

    afterEach(() => {
      Object.defineProperty(process.stdout, "columns", {
        value: originalColumns,
        writable: true,
        configurable: true,
      });
    });

    it("returns minimum widths when fullWidth is false", () => {
      const widths = computeColumnWidths(COLUMNS, false);
      expect(widths).toEqual([5, 20, 10]);
    });

    it("expands columns proportionally for wide terminals", () => {
      Object.defineProperty(process.stdout, "columns", {
        value: 71,
        writable: true,
        configurable: true,
      });
      // available = 71 - 1 (padding) = 70, totalMin = 35, so columns double
      const widths = computeColumnWidths(COLUMNS, true);
      expect(widths.reduce((a, b) => a + b, 0)).toBe(70);
      // proportional: each column roughly doubles
      expect(widths[0]).toBeGreaterThanOrEqual(5);
      expect(widths[1]).toBeGreaterThanOrEqual(20);
      expect(widths[2]).toBeGreaterThanOrEqual(10);
    });

    it("shrinks columns proportionally when terminal is narrower than total", () => {
      Object.defineProperty(process.stdout, "columns", {
        value: 36,
        writable: true,
        configurable: true,
      });
      // available = 36 - 1 = 35, totalBase = 35, so columns stay the same
      const widths = computeColumnWidths(COLUMNS, true);
      expect(widths).toEqual([5, 20, 10]);
    });

    it("returns base widths when terminal is narrower than total", () => {
      Object.defineProperty(process.stdout, "columns", {
        value: 19,
        writable: true,
        configurable: true,
      });
      // available = 18 < totalBase = 35, so columns stay at base widths
      const widths = computeColumnWidths(COLUMNS, true);
      expect(widths).toEqual([5, 20, 10]);
    });

    it("distributes remainder across columns", () => {
      Object.defineProperty(process.stdout, "columns", {
        value: 41,
        writable: true,
        configurable: true,
      });
      // available = 40, totalMin = 35, extra = 5
      const widths = computeColumnWidths(COLUMNS, true);
      expect(widths.reduce((a, b) => a + b, 0)).toBe(40);
    });
  });
});
