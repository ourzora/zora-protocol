import { afterEach, describe, expect, it, vi } from "vitest";
import { glibcOlderThan, shouldUseLowGlibcSdk } from "./load-xmtp-sdk.js";

describe("glibcOlderThan", () => {
  it("compares by major then minor (numeric, not lexical)", () => {
    expect(glibcOlderThan("2.35", "2.38")).toBe(true);
    expect(glibcOlderThan("2.36", "2.38")).toBe(true);
    expect(glibcOlderThan("2.9", "2.38")).toBe(true); // 9 < 38 numerically
    expect(glibcOlderThan("2.38", "2.38")).toBe(false);
    expect(glibcOlderThan("2.39", "2.38")).toBe(false);
    expect(glibcOlderThan("2.41", "2.38")).toBe(false);
    expect(glibcOlderThan("3.0", "2.38")).toBe(false);
  });
});

describe("shouldUseLowGlibcSdk", () => {
  const origPlatform = process.platform;
  const setPlatform = (p: string) =>
    Object.defineProperty(process, "platform", { value: p, configurable: true });
  const mockGlibc = (v: string | undefined) =>
    vi.spyOn(process.report, "getReport").mockReturnValue({
      header: v ? { glibcVersionRuntime: v } : {},
    });

  afterEach(() => {
    setPlatform(origPlatform);
    vi.restoreAllMocks();
  });

  it("is false on macOS/Windows regardless of report", () => {
    mockGlibc("2.36");
    setPlatform("darwin");
    expect(shouldUseLowGlibcSdk()).toBe(false);
    setPlatform("win32");
    expect(shouldUseLowGlibcSdk()).toBe(false);
  });

  it("is false on musl Linux (no glibc version reported)", () => {
    setPlatform("linux");
    mockGlibc(undefined);
    expect(shouldUseLowGlibcSdk()).toBe(false);
  });

  it("is true on glibc Linux below the floor (Ubuntu 22.04 / Debian 12)", () => {
    setPlatform("linux");
    mockGlibc("2.35");
    expect(shouldUseLowGlibcSdk()).toBe(true);
  });

  it("is false on glibc Linux at or above the floor (Ubuntu 24.04+)", () => {
    setPlatform("linux");
    mockGlibc("2.39");
    expect(shouldUseLowGlibcSdk()).toBe(false);
  });
});
