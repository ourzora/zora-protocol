import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { afterEach, describe, expect, it } from "vitest";
import { detectAgentHarness, mapAgentHarnessToUapi } from "./agent-harness.js";

describe("detectAgentHarness", () => {
  let tempDir: string | null = null;

  afterEach(() => {
    if (tempDir) rmSync(tempDir, { recursive: true, force: true });
    tempDir = null;
  });

  it("returns undefined when no known harness directory exists", () => {
    tempDir = mkdtempSync(join(tmpdir(), "zora-agent-harness-"));
    expect(detectAgentHarness(tempDir)).toBeUndefined();
  });

  it("detects a known harness directory", () => {
    tempDir = mkdtempSync(join(tmpdir(), "zora-agent-harness-"));
    mkdirSync(join(tempDir, ".cursor"));

    expect(detectAgentHarness(tempDir)).toBe("cursor");
  });

  it("uses the configured detection priority when multiple harnesses exist", () => {
    tempDir = mkdtempSync(join(tmpdir(), "zora-agent-harness-"));
    mkdirSync(join(tempDir, ".windsurf"));
    mkdirSync(join(tempDir, ".claude"));

    expect(detectAgentHarness(tempDir)).toBe("claude");
  });
});

describe("mapAgentHarnessToUapi", () => {
  it("maps local harness ids to the accepted UAPI enum values", () => {
    expect(mapAgentHarnessToUapi("claude")).toBe("CLAUDE");
    expect(mapAgentHarnessToUapi("cursor")).toBe("CURSOR");
    expect(mapAgentHarnessToUapi("windsurf")).toBe("WINDSURF");
    expect(mapAgentHarnessToUapi("openclaw")).toBe("OPENCLAW");
    expect(mapAgentHarnessToUapi("hermes")).toBe("HERMES");
  });
});
