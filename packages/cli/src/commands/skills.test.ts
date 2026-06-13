import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
}));

import { createProgram } from "../test/create-program.js";
import { skillsCommand } from "./skills.js";

const mockFetchOk = (body: string) =>
  vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(() =>
      Promise.resolve(new Response(body, { status: 200 })),
    );

const mockFetchFail = () =>
  vi
    .spyOn(globalThis, "fetch")
    .mockImplementation(() =>
      Promise.resolve(new Response("Not Found", { status: 404 })),
    );

describe("skills list", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("lists the skills with categories and descriptions", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "list"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("onboarding");
    expect(output).toContain("copy-trader");
    expect(output).toContain("early-buyer");
    expect(output).toContain("watchlist");
    expect(output).toContain("take-profit");
    expect(output).not.toContain("/zora-");
  });

  it("returns JSON output with --json", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["--json", "skills", "list"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    expect(parsed.skills).toHaveLength(5);
    expect(parsed.skills.map((s: { name: string }) => s.name)).toEqual([
      "onboarding",
      "copy-trader",
      "early-buyer",
      "watchlist",
      "take-profit",
    ]);
  });
});

describe("skills add", () => {
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    // suppress console.log output; not asserted on in these tests
    vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    tmpDir = mkdtempSync(join(tmpdir(), "zora-skills-test-"));
    originalCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(originalCwd);
    rmSync(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it("installs a skill to .claude/skills/zora-<name>/SKILL.md by default", async () => {
    mockFetchOk("# Skill body");

    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "add", "copy-trader"], {
      from: "user",
    });

    const skillPath = join(tmpDir, ".claude/skills/zora-copy-trader/SKILL.md");
    expect(existsSync(skillPath)).toBe(true);
    expect(readFileSync(skillPath, "utf8")).toBe("# Skill body");
  });

  it("installs all skills with --all", async () => {
    mockFetchOk("# body");

    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "add", "--all"], { from: "user" });

    for (const name of [
      "onboarding",
      "copy-trader",
      "early-buyer",
      "watchlist",
      "take-profit",
    ]) {
      expect(
        existsSync(join(tmpDir, ".claude/skills", `zora-${name}`, "SKILL.md")),
      ).toBe(true);
    }
  });

  it("respects --agent cursor", async () => {
    mockFetchOk("# body");

    const program = createProgram(skillsCommand);
    await program.parseAsync(
      ["skills", "add", "copy-trader", "--agent", "cursor"],
      { from: "user" },
    );

    expect(
      existsSync(join(tmpDir, ".cursor/skills/zora-copy-trader/SKILL.md")),
    ).toBe(true);
  });

  it("respects --dir override", async () => {
    mockFetchOk("# body");

    const program = createProgram(skillsCommand);
    await program.parseAsync(
      ["skills", "add", "copy-trader", "--dir", "custom-dir"],
      { from: "user" },
    );

    expect(
      existsSync(join(tmpDir, "custom-dir/zora-copy-trader/SKILL.md")),
    ).toBe(true);
  });

  it("errors on unknown skill name", async () => {
    const program = createProgram(skillsCommand);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => {
      throw new Error("exit");
    });
    await expect(
      program.parseAsync(["skills", "add", "bogus"], { from: "user" }),
    ).rejects.toThrow();
    const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("Unknown skill");
    exitSpy.mockRestore();
  });

  it("exits with error when fetch fails for all skills", async () => {
    mockFetchFail();

    const program = createProgram(skillsCommand);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => {
      throw new Error("exit");
    });
    await expect(
      program.parseAsync(["skills", "add", "copy-trader"], { from: "user" }),
    ).rejects.toThrow();
    const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("Failed to install");
    exitSpy.mockRestore();
  });
});
