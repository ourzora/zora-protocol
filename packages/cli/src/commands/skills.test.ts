import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
}));

import { createProgram } from "../test/create-program.js";
import { skillsCommand, computeIntegrity, SKILLS } from "./skills.js";

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
    expect(parsed.skills).toHaveLength(15);
    expect(parsed.skills.map((s: { name: string }) => s.name)).toEqual([
      // Onboarding
      "onboarding",
      // Discovery
      "early-buyer",
      "watchlist",
      "trend-sniper",
      "new-coin-screener",
      "whale-watcher",
      // Social
      "copy-trader",
      "dm-responder",
      "comment-engager",
      "social-trader",
      "auto-poster",
      // Risk
      "take-profit",
      "dca",
      "portfolio-rebalancer",
      // Reporting
      "portfolio-digest",
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
    await program.parseAsync(
      ["skills", "add", "copy-trader", "--skip-verify"],
      {
        from: "user",
      },
    );

    const skillPath = join(tmpDir, ".claude/skills/zora-copy-trader/SKILL.md");
    expect(existsSync(skillPath)).toBe(true);
    expect(readFileSync(skillPath, "utf8")).toBe("# Skill body");
  });

  it("installs all skills with --all", async () => {
    mockFetchOk("# body");

    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "add", "--all", "--skip-verify"], {
      from: "user",
    });

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
      ["skills", "add", "copy-trader", "--agent", "cursor", "--skip-verify"],
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
      ["skills", "add", "copy-trader", "--dir", "custom-dir", "--skip-verify"],
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
      program.parseAsync(["skills", "add", "copy-trader", "--skip-verify"], {
        from: "user",
      }),
    ).rejects.toThrow();
    const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("Failed to install");
    exitSpy.mockRestore();
  });
});

describe("skills integrity verification", () => {
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    tmpDir = mkdtempSync(join(tmpdir(), "zora-skills-integrity-test-"));
    originalCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(originalCwd);
    rmSync(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it("fails installation when integrity check fails", async () => {
    mockFetchOk("# Different content that won't match hash");

    const program = createProgram(skillsCommand);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => {
      throw new Error("exit");
    });

    await expect(
      program.parseAsync(["skills", "add", "copy-trader"], { from: "user" }),
    ).rejects.toThrow();

    const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("integrity check failed");
    expect(output).toContain("--skip-verify");

    exitSpy.mockRestore();
  });

  it("skips integrity check with --skip-verify", async () => {
    mockFetchOk("# Any content that doesn't match hash");

    const program = createProgram(skillsCommand);
    await program.parseAsync(
      ["skills", "add", "copy-trader", "--skip-verify"],
      { from: "user" },
    );

    expect(
      existsSync(join(tmpDir, ".claude/skills/zora-copy-trader/SKILL.md")),
    ).toBe(true);
  });

  it("includes expected and received hashes in error message", async () => {
    const content = "# Tampered content";
    mockFetchOk(content);

    const program = createProgram(skillsCommand);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => {
      throw new Error("exit");
    });

    await expect(
      program.parseAsync(["skills", "add", "copy-trader"], { from: "user" }),
    ).rejects.toThrow();

    const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
    const actualHash = computeIntegrity(content);
    expect(output).toContain("Expected:");
    expect(output).toContain("Received:");
    expect(output).toContain(actualHash);

    exitSpy.mockRestore();
  });

  it("exits non-zero when --all has all integrity failures", async () => {
    // Mock fetch to return content that won't match any hash
    let callCount = 0;
    vi.spyOn(globalThis, "fetch").mockImplementation(() => {
      callCount++;
      return Promise.resolve(
        new Response(`# Content ${callCount}`, { status: 200 }),
      );
    });

    const program = createProgram(skillsCommand);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => {
      throw new Error("exit");
    });

    await expect(
      program.parseAsync(["skills", "add", "--all"], { from: "user" }),
    ).rejects.toThrow();

    const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("integrity check failed");

    exitSpy.mockRestore();
  });

  it("exits non-zero when partial install has integrity failures (some succeed, some fail)", async () => {
    // This tests the partial-failure path (lines 350-387 in skills.ts)
    // where installed.length > 0 AND hasIntegrityErrors is true
    const logSpy = vi.spyOn(console, "log");

    // Create content that will match the first skill's hash
    const validContent = "# Valid skill content for test";
    const validHash = computeIntegrity(validContent);

    // Temporarily patch the first skill's hash to match our test content
    const originalHash = SKILLS[0].integrity;
    SKILLS[0].integrity = validHash;

    // Mock fetch: first skill returns matching content, rest return non-matching
    let callCount = 0;
    vi.spyOn(globalThis, "fetch").mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        // First skill (onboarding) - content matches patched hash
        return Promise.resolve(new Response(validContent, { status: 200 }));
      }
      // All other skills - content won't match their real hashes
      return Promise.resolve(
        new Response(`# Tampered content ${callCount}`, { status: 200 }),
      );
    });

    const program = createProgram(skillsCommand);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => {
      throw new Error("exit");
    });

    try {
      // Install all skills - first will pass, rest will fail integrity
      await expect(
        program.parseAsync(["skills", "add", "--all"], { from: "user" }),
      ).rejects.toThrow();

      // Verify first skill WAS installed (partial success)
      expect(
        existsSync(join(tmpDir, ".claude/skills/zora-onboarding/SKILL.md")),
      ).toBe(true);

      // Verify second skill was NOT installed (integrity failure)
      expect(
        existsSync(join(tmpDir, ".claude/skills/zora-early-buyer/SKILL.md")),
      ).toBe(false);

      // Verify integrity error message and warning appear
      const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(output).toContain("integrity check failed");
      expect(output).toContain("compromised downloads");
    } finally {
      // Restore original hash
      SKILLS[0].integrity = originalHash;
      exitSpy.mockRestore();
      logSpy.mockRestore();
    }
  });
});

describe("skills list JSON output", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("does not include integrity field in JSON output", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["--json", "skills", "list"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);

    // Verify integrity field is not present in any skill
    for (const skill of parsed.skills) {
      expect(skill).not.toHaveProperty("integrity");
      expect(skill).toHaveProperty("name");
      expect(skill).toHaveProperty("category");
      expect(skill).toHaveProperty("description");
    }
  });
});
