import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";

// Mock truecolor support so tests run in any terminal
vi.mock("../lib/zorb-pixels.js", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../lib/zorb-pixels.js")>();
  return {
    ...actual,
    supportsTruecolor: () => true,
  };
});

// Dynamic import after mock is set up
const { Zorb } = await import("./Zorb.js");

describe("Zorb", () => {
  it("renders without crashing", () => {
    const { lastFrame } = render(<Zorb size={10} />);
    expect(lastFrame()).toBeTruthy();
  });

  it("contains half-block characters", () => {
    const { lastFrame } = render(<Zorb size={10} />);
    const frame = lastFrame()!;
    const hasHalfBlock = frame.includes("\u2584") || frame.includes("\u2580");
    expect(hasHalfBlock).toBe(true);
  });

  it("produces the correct number of rows (size / 2)", () => {
    const size = 10;
    const { lastFrame } = render(<Zorb size={size} />);
    const frame = lastFrame()!;
    const lines = frame.split("\n");
    expect(lines).toHaveLength(size / 2 + 2);
  });

  it("returns null when truecolor is not supported", async () => {
    vi.resetModules();
    vi.doMock("../lib/zorb-pixels.js", async (importOriginal) => {
      const actual =
        await importOriginal<typeof import("../lib/zorb-pixels.js")>();
      return {
        ...actual,
        supportsTruecolor: () => false,
      };
    });
    const { Zorb: ZorbNoColor } = await import("./Zorb.js");
    const { lastFrame } = render(<ZorbNoColor size={10} />);
    expect(lastFrame()).toBe("");
  });
});
