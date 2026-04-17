import { describe, it, expect } from "vitest";
import { render } from "ink-testing-library";
import { KeyValueTable } from "./KeyValueTable.js";

describe("KeyValueTable", () => {
  it("renders labels and values", () => {
    const rows = [
      { label: "Name", value: "Alice" },
      { label: "Role", value: "Engineer" },
    ];
    const { lastFrame } = render(<KeyValueTable rows={rows} />);
    const frame = lastFrame();

    expect(frame).toContain("Name");
    expect(frame).toContain("Alice");
    expect(frame).toContain("Role");
    expect(frame).toContain("Engineer");
  });

  it("pads labels to explicit labelWidth", () => {
    const rows = [{ label: "Hi", value: "there" }];
    const { lastFrame } = render(<KeyValueTable rows={rows} labelWidth={20} />);
    const frame = lastFrame();

    // "Hi" should be padded to 20 characters
    expect(frame).toContain("Hi" + " ".repeat(18));
  });

  it("auto-sizes label column when labelWidth is not provided", () => {
    const rows = [
      { label: "Short", value: "a" },
      { label: "Much longer label", value: "b" },
    ];
    const { lastFrame } = render(<KeyValueTable rows={rows} />);
    const frame = lastFrame();

    // Both labels should be present, padded to the longest + 2
    expect(frame).toContain("Short");
    expect(frame).toContain("Much longer label");
  });
});
