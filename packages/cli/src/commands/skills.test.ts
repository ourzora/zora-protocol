import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
  identify: vi.fn(),
  shutdownAnalytics: vi.fn(),
}));

// Importing the full `buildProgram` pulls in every command module. `../lib/config.js`
// resolves the config directory at module load (via os.homedir()), which is unsafe
// under vitest, so mock it out — the skills command itself never touches config.
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
  getPrivateKey: vi.fn(),
  getSmartWalletAddress: vi.fn(),
  getAgentWallet: vi.fn(),
  isAgentWallet: vi.fn(),
  peekAgentWallet: vi.fn(),
  getEnvApiKey: vi.fn(),
  getAnalyticsId: vi.fn(),
  getDmCheckAt: vi.fn(),
  saveDmCheckAt: vi.fn(),
  getPrivySession: vi.fn(),
  getBudget: vi.fn(),
}));

// buildProgram's postAction hook surfaces new DMs; stub it out so the full-program
// regression tests below don't hit the network or filesystem for messaging.
vi.mock("../messaging/notify.js", () => ({
  maybeNotifyNewDms: vi.fn().mockResolvedValue(undefined),
}));

import { createProgram } from "../test/create-program.js";
import { buildProgram } from "../index.js";
import { skillsCommand, SKILLS } from "./skills.js";
import { SKILL_CONTENT } from "../generated/skill-content.js";

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
    expect(output).toContain("pay");
    expect(output).not.toContain("/zora-");
  });

  it("returns JSON output with --json", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["--json", "skills", "list"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    expect(parsed.skills).toHaveLength(17);
    expect(parsed.skills.map((s: { name: string }) => s.name)).toEqual([
      // Core
      "cli",
      // Payments
      "pay",
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

  it("does not include the bundled content in list output", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["--json", "skills", "list"], { from: "user" });

    const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
    const parsed = JSON.parse(output);
    for (const skill of parsed.skills) {
      expect(skill).not.toHaveProperty("integrity");
      expect(skill).not.toHaveProperty("content");
      expect(skill).toHaveProperty("name");
      expect(skill).toHaveProperty("category");
      expect(skill).toHaveProperty("description");
    }
  });
});

describe("bundled skill content", () => {
  it("has content for every skill in the SKILLS list", () => {
    for (const skill of SKILLS) {
      expect(typeof SKILL_CONTENT[skill.name]).toBe("string");
      expect(SKILL_CONTENT[skill.name].length).toBeGreaterThan(0);
    }
  });

  it("registers the x402 pay skill with matching content", () => {
    const pay = SKILLS.find((s) => s.name === "pay");
    expect(pay).toBeDefined();
    expect(pay!.category).toBe("Payments");
    const content = SKILL_CONTENT["pay"];
    expect(content).toContain("x402");
    expect(content).toContain("PAYMENT-SIGNATURE");
    expect(content).toContain("--max-value");
  });

  it("does not embed content for skills missing from the SKILLS list", () => {
    // The generator discovers skills from the filesystem, so a skill directory
    // added without a SKILLS entry would be bundled but never installable. Catch
    // that orphaned content here.
    const registered = new Set(SKILLS.map((s) => s.name));
    for (const name of Object.keys(SKILL_CONTENT)) {
      expect(
        registered.has(name),
        `${name} is embedded but not registered in SKILLS`,
      ).toBe(true);
    }
  });

  it("does not instruct the agent to fetch the core skill over the network", () => {
    // The runtime fetch of the core skill from agents.zora.com was an unverified
    // remote-fetch surface (SEC-250 / SEC-259). The core skill is now installed
    // locally alongside every strategy skill, so no skill should fetch it.
    for (const [name, content] of Object.entries(SKILL_CONTENT)) {
      expect(content, `${name} still fetches the core skill`).not.toContain(
        "fetch the core skill at",
      );
      expect(
        content,
        `${name} still references skill.md over http`,
      ).not.toMatch(/https?:\/\/[^\s)]*\/skill\.md/);
    }
  });
});

describe("skills add", () => {
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let fetchSpy: ReturnType<typeof vi.spyOn>;
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    // suppress console.log output; not asserted on in these tests
    vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    // Installs must not touch the network — fail loudly if anything calls fetch.
    fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(() => {
      throw new Error("network access is not allowed during skill install");
    });
    tmpDir = mkdtempSync(join(tmpdir(), "zora-skills-test-"));
    originalCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(originalCwd);
    rmSync(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it("installs a skill from the bundle to .claude/skills/zora-<name>/SKILL.md", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "add", "copy-trader"], {
      from: "user",
    });

    const skillPath = join(tmpDir, ".claude/skills/zora-copy-trader/SKILL.md");
    expect(existsSync(skillPath)).toBe(true);
    expect(readFileSync(skillPath, "utf8")).toBe(SKILL_CONTENT["copy-trader"]);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("also installs the core cli skill alongside a strategy skill", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "add", "early-buyer"], {
      from: "user",
    });

    const corePath = join(tmpDir, ".claude/skills/zora-cli/SKILL.md");
    expect(existsSync(corePath)).toBe(true);
    expect(readFileSync(corePath, "utf8")).toBe(SKILL_CONTENT["cli"]);
  });

  it("does not duplicate the core skill when installing cli directly", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "add", "cli"], { from: "user" });

    expect(existsSync(join(tmpDir, ".claude/skills/zora-cli/SKILL.md"))).toBe(
      true,
    );
    // No strategy skill requested, so nothing else should be installed.
    expect(
      existsSync(join(tmpDir, ".claude/skills/zora-copy-trader/SKILL.md")),
    ).toBe(false);
  });

  it("installs all skills with --all", async () => {
    const program = createProgram(skillsCommand);
    await program.parseAsync(["skills", "add", "--all"], {
      from: "user",
    });

    for (const name of SKILLS.map((s) => s.name)) {
      expect(
        existsSync(join(tmpDir, ".claude/skills", `zora-${name}`, "SKILL.md")),
      ).toBe(true);
    }
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("respects --agent cursor", async () => {
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
});

// These tests drive the FULL `buildProgram()` rather than `createProgram`, because
// the bug they guard against lived in the root program's `preAction` help-guard hook
// (index.tsx), not in the skills command itself. The hook shows help and exits when a
// command declares a positional arg but none is passed — which wrongly killed
// `skills add --all` (no name needed). `createProgram` doesn't install that hook, so
// command-level tests can't catch this regression.
describe("skills add via full program (preAction help-guard)", () => {
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    tmpDir = mkdtempSync(join(tmpdir(), "zora-skills-program-test-"));
    originalCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(originalCwd);
    rmSync(tmpDir, { recursive: true, force: true });
    vi.restoreAllMocks();
  });

  it("installs all skills with --all and no positional name", async () => {
    const program = buildProgram();
    await program.parseAsync(["skills", "add", "--all"], {
      from: "user",
    });

    for (const name of SKILLS.map((s) => s.name)) {
      expect(
        existsSync(join(tmpDir, ".claude/skills", `zora-${name}`, "SKILL.md")),
      ).toBe(true);
    }
  });

  it("installs a single skill by name through the full program", async () => {
    const program = buildProgram();
    await program.parseAsync(["skills", "add", "copy-trader"], {
      from: "user",
    });

    expect(
      existsSync(join(tmpDir, ".claude/skills/zora-copy-trader/SKILL.md")),
    ).toBe(true);
  });

  // With "skills add" exempt from the preAction help-guard, this no longer prints
  // help — the action runs and its own validation rejects the missing argument.
  it("errors and exits non-zero when neither a name nor --all is given", async () => {
    const program = buildProgram();
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => {
      throw new Error("exit");
    });

    await expect(
      program.parseAsync(["skills", "add"], { from: "user" }),
    ).rejects.toThrow();

    // The action's own validation fires (not the help-guard hook).
    const output = errorSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(output).toContain("Missing skill name");
    // No skills directory should have been created.
    expect(existsSync(join(tmpDir, ".claude/skills"))).toBe(false);
    exitSpy.mockRestore();
  });
});
