import { describe, it, expect } from "vitest";
import { render } from "ink-testing-library";
import { TableComponent, truncate, type Column } from "./table.js";

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
      <TableComponent data={DATA.slice(0, 1)} columns={COLUMNS} />,
    );
    const frame = lastFrame();
    expect(frame).toContain("#");
    expect(frame).toContain("Name");
    expect(frame).toContain("Value");
  });

  it("renders row data with correct values", () => {
    const { lastFrame } = render(
      <TableComponent data={DATA} columns={COLUMNS} />,
    );
    const frame = lastFrame();
    expect(frame).toContain("Alpha");
    expect(frame).toContain("Beta");
    expect(frame).toContain("$100");
  });

  it("renders title when provided", () => {
    const { lastFrame } = render(
      <TableComponent
        data={DATA.slice(0, 1)}
        columns={COLUMNS}
        title="Top Coins"
        subtitle="3 results"
      />,
    );
    const frame = lastFrame();
    expect(frame).toContain("Top Coins");
    expect(frame).toContain("3 results");
  });

  it("renders without title", () => {
    const { lastFrame } = render(
      <TableComponent data={DATA.slice(0, 1)} columns={COLUMNS} />,
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
      <TableComponent data={data} columns={columns} />,
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
      <TableComponent data={data} columns={columns} />,
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
});
