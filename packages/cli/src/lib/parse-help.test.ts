import { describe, it, expect } from "vitest";
import { parseHelpSections, getDescriptionColumnOffset } from "./parse-help.js";

const SAMPLE_HELP = `Usage: zora [options] [command]

A developer CLI for the Zora platform

Options:
  --json     Output as JSON (for scripts and automation) (default: false)
  -V, --version  Display version number
  -h, --help     Display help for command

Commands:
  buy <coin>                            Buy a coin
  sell <coin>                           Sell a coin
  explore [options]                     Browse top coins
`;

describe("parseHelpSections", () => {
  it("parses Commander help text into titled sections", () => {
    const sections = parseHelpSections(SAMPLE_HELP);

    expect(sections).toHaveLength(3);
    expect(sections[0].title).toBe("Usage");
    expect(sections[1].title).toBe("Options");
    expect(sections[2].title).toBe("Commands");
  });

  it("strips 2-space Commander indent from content", () => {
    const sections = parseHelpSections(SAMPLE_HELP);
    const options = sections.find((s) => s.title === "Options")!;

    expect(options.content).not.toMatch(/^  /m);
    expect(options.content).toContain("--json");
  });

  it("captures inline content after the section header colon", () => {
    const text = `Usage: zora [options]

Options:
  --help  Show help
`;
    const sections = parseHelpSections(text);
    const usage = sections.find((s) => s.title === "Usage")!;

    expect(usage.content).toBe("zora [options]");
  });

  it("filters out empty sections", () => {
    const text = `Usage: zora

Empty:

Options:
  --help  Show help
`;
    const sections = parseHelpSections(text);

    expect(sections.map((s) => s.title)).not.toContain("Empty");
  });

  it("returns empty array for text with no sections", () => {
    expect(parseHelpSections("just some plain text")).toEqual([]);
  });

  it("trims leading and trailing newlines from section content", () => {
    const text = `Options:

  --help  Show help

`;
    const sections = parseHelpSections(text);

    expect(sections[0].content).toBe("--help  Show help");
  });
});

describe("getDescriptionColumnOffset", () => {
  it("detects the description column offset from two-column sections", () => {
    const sections = parseHelpSections(SAMPLE_HELP);
    const offset = getDescriptionColumnOffset(sections);

    // "  buy <coin>" is 12 chars + padding to column 40
    // After indent stripping: "buy <coin>" (10 chars) + spaces to description
    expect(offset).toBeGreaterThan(0);
    expect(offset).toBeLessThan(80);
  });

  it("returns 38 as default when no two-column content is found", () => {
    const sections = [{ title: "Usage", content: "zora [options]" }];

    expect(getDescriptionColumnOffset(sections)).toBe(38);
  });

  it("returns 38 for empty sections array", () => {
    expect(getDescriptionColumnOffset([])).toBe(38);
  });

  it("uses the first two-column section it finds", () => {
    const sections = [
      { title: "Usage", content: "zora [options]" },
      { title: "Commands", content: "buy <coin>   Buy a coin" },
      { title: "Other", content: "sell <coin>     Sell a coin" },
    ];
    const offset = getDescriptionColumnOffset(sections);

    // "buy <coin>" (10) + "   " (3) = 13
    expect(offset).toBe(13);
  });
});
