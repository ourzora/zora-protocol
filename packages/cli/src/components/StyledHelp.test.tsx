import { describe, it, expect } from "vitest";
import { render } from "ink-testing-library";
import { Text } from "ink";
import { StyledHelp } from "./StyledHelp.js";

const TWO_COLUMN_SECTIONS = [
  {
    title: "Commands",
    content:
      "buy <coin>                            Buy a coin\nsell <coin>                           Sell a coin",
  },
];

const SINGLE_COLUMN_SECTIONS = [
  { title: "Usage", content: "zora [options] [command]" },
];

describe("StyledHelp", () => {
  it("renders section titles", () => {
    const { lastFrame } = render(<StyledHelp sections={TWO_COLUMN_SECTIONS} />);
    const frame = lastFrame();

    expect(frame).toContain("Commands");
  });

  it("renders two-column sections as key-value pairs", () => {
    const { lastFrame } = render(<StyledHelp sections={TWO_COLUMN_SECTIONS} />);
    const frame = lastFrame();

    expect(frame).toContain("buy <coin>");
    expect(frame).toContain("Buy a coin");
    expect(frame).toContain("sell <coin>");
    expect(frame).toContain("Sell a coin");
  });

  it("renders single-column sections as plain text", () => {
    const { lastFrame } = render(
      <StyledHelp sections={SINGLE_COLUMN_SECTIONS} />,
    );
    const frame = lastFrame();

    expect(frame).toContain("zora [options] [command]");
  });

  it("renders optional header above sections", () => {
    const header = <Text>My Header</Text>;
    const { lastFrame } = render(
      <StyledHelp sections={SINGLE_COLUMN_SECTIONS} header={header} />,
    );
    const frame = lastFrame();

    expect(frame).toContain("My Header");
    expect(frame).toContain("Usage");
  });

  it("renders without header when not provided", () => {
    const { lastFrame } = render(
      <StyledHelp sections={SINGLE_COLUMN_SECTIONS} />,
    );
    const frame = lastFrame();

    expect(frame).toContain("Usage");
  });

  it("renders multiple sections", () => {
    const sections = [...SINGLE_COLUMN_SECTIONS, ...TWO_COLUMN_SECTIONS];
    const { lastFrame } = render(<StyledHelp sections={sections} />);
    const frame = lastFrame();

    expect(frame).toContain("Usage");
    expect(frame).toContain("Commands");
  });
});
