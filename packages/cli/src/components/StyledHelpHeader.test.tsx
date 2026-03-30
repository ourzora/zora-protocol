import { describe, it, expect } from "vitest";
import { render } from "ink-testing-library";
import { StyledHelpHeader } from "./StyledHelpHeader.js";

const SECTIONS = [
  {
    title: "Commands",
    content: "buy <coin>                            Buy a coin",
  },
];

describe("StyledHelpHeader", () => {
  it("renders the CLI title", () => {
    const { lastFrame } = render(<StyledHelpHeader sections={SECTIONS} />);
    const frame = lastFrame();

    expect(frame).toContain("Zora CLI");
  });
});
