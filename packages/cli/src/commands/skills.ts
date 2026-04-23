import { Command } from "commander";
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { track } from "../lib/analytics.js";

const DEFAULT_SKILLS_BASE_URL = "https://zoraskills.dev/skill";
const SHARED_FILE = "cli-setup";

const getSkillsBaseUrl = (): string =>
  process.env.ZORA_SKILLS_BASE_URL || DEFAULT_SKILLS_BASE_URL;

type SkillMeta = {
  name: string;
  category: string;
  description: string;
};

const SKILLS: SkillMeta[] = [
  {
    name: "copy-trader",
    category: "Social",
    description:
      "Mirror another user's trades — existing holdings, future trades, or both",
  },
  {
    name: "early-buyer",
    category: "Discovery",
    description: "Auto-buy new coin launches from creators you follow",
  },
  {
    name: "watchlist",
    category: "Discovery",
    description:
      "Track coins and alert when market cap hits configured thresholds",
  },
  {
    name: "take-profit",
    category: "Risk",
    description:
      "Auto-sell positions at configured take-profit or stop-loss price targets",
  },
];

type Agent = "claude" | "cursor" | "windsurf";

const AGENT_COMMAND_DIRS: Record<Agent, string> = {
  claude: ".claude/commands",
  cursor: ".cursor/commands",
  windsurf: ".windsurf/commands",
};

const AGENT_ROOT_DIRS: Record<Agent, string> = {
  claude: ".claude",
  cursor: ".cursor",
  windsurf: ".windsurf",
};

const detectAgent = (cwd: string): Agent | null => {
  const order: Agent[] = ["claude", "cursor", "windsurf"];
  for (const agent of order) {
    if (existsSync(join(cwd, AGENT_ROOT_DIRS[agent]))) return agent;
  }
  return null;
};

const fetchSkill = async (name: string): Promise<string> => {
  const url = `${getSkillsBaseUrl()}/${name}.md`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(
      `Failed to fetch ${url}: ${response.status} ${response.statusText}`,
    );
  }
  return response.text();
};

export const skillsCommand = new Command("skills")
  .description(
    "Install pre-built agent trading skills (copy-trader, early-buyer, watchlist, take-profit)",
  )
  .action(function (this: Command) {
    this.outputHelp();
  });

skillsCommand
  .command("list")
  .description("List available skills")
  .action(function (this: Command) {
    const json = getJson(this);
    outputData(json, {
      json: { skills: SKILLS },
      render: () => {
        console.log("Available skills:\n");
        for (const s of SKILLS) {
          console.log(`  /${s.name.padEnd(14)} ${s.description}`);
        }
        console.log("\nInstall with: zora skills add <name>");
      },
    });
    track("cli_skills_list", { output_format: json ? "json" : "text" });
  });

skillsCommand
  .command("add [name]")
  .description(
    "Install a skill into your agent's commands directory (auto-detects .claude, .cursor, .windsurf)",
  )
  .option("--all", "Install all skills")
  .option(
    "--agent <agent>",
    "Target agent: claude, cursor, windsurf (default: auto-detect)",
  )
  .option("--dir <path>", "Explicit directory to install into")
  .action(async function (this: Command, name?: string) {
    const json = getJson(this);
    const opts = this.opts();
    const installAll = opts.all === true;
    const agentFlag = opts.agent as Agent | undefined;
    const dirFlag = opts.dir as string | undefined;

    if (!installAll && !name) {
      return outputErrorAndExit(
        json,
        "Missing skill name.",
        "Usage: zora skills add <name> or zora skills add --all",
      );
    }
    if (installAll && name) {
      return outputErrorAndExit(
        json,
        "Cannot specify both a name and --all.",
        `Use one or the other: zora skills add ${name} or zora skills add --all`,
      );
    }

    let outDir: string;
    let resolvedAgent: Agent | "custom" | null = null;
    if (dirFlag) {
      outDir = resolve(dirFlag);
      resolvedAgent = "custom";
    } else if (agentFlag) {
      if (!AGENT_COMMAND_DIRS[agentFlag]) {
        return outputErrorAndExit(
          json,
          `Unknown agent: ${agentFlag}`,
          "Supported: claude, cursor, windsurf",
        );
      }
      outDir = resolve(process.cwd(), AGENT_COMMAND_DIRS[agentFlag]);
      resolvedAgent = agentFlag;
    } else {
      const detected = detectAgent(process.cwd());
      resolvedAgent = detected ?? "claude";
      outDir = resolve(process.cwd(), AGENT_COMMAND_DIRS[resolvedAgent]);
    }

    const names = installAll ? SKILLS.map((s) => s.name) : [name!];
    const invalid = names.filter((n) => !SKILLS.some((s) => s.name === n));
    if (invalid.length > 0) {
      return outputErrorAndExit(
        json,
        `Unknown skill: ${invalid.join(", ")}`,
        `Available: ${SKILLS.map((s) => s.name).join(", ")}`,
      );
    }

    mkdirSync(outDir, { recursive: true });

    const installed: { name: string; path: string }[] = [];
    const errors: { name: string; error: string }[] = [];

    const filesToFetch = [...names, SHARED_FILE];
    for (const file of filesToFetch) {
      try {
        const content = await fetchSkill(file);
        const outPath = join(outDir, `${file}.md`);
        writeFileSync(outPath, content);
        installed.push({ name: file, path: outPath });
      } catch (err) {
        errors.push({
          name: file,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    if (errors.length > 0 && installed.length === 0) {
      return outputErrorAndExit(
        json,
        `Failed to install: ${errors.map((e) => e.name).join(", ")}`,
        "Check your network connection and retry.",
      );
    }

    outputData(json, {
      json: {
        installed,
        errors: errors.length > 0 ? errors : undefined,
        agent: resolvedAgent,
        dir: outDir,
      },
      render: () => {
        if (resolvedAgent && resolvedAgent !== "custom") {
          console.log(`\x1b[2mDetected agent: ${resolvedAgent}\x1b[0m`);
        }
        for (const { name, path } of installed) {
          console.log(`\x1b[32m✓\x1b[0m Installed ${name} → ${path}`);
        }
        for (const { name, error } of errors) {
          console.error(`\x1b[31m✗\x1b[0m ${name}: ${error}`);
        }
        const skillsInstalled = installed.filter((i) => i.name !== SHARED_FILE);
        if (skillsInstalled.length > 0) {
          const firstSkill = skillsInstalled[0]!.name;
          console.log(
            `\nInvoke by typing /${firstSkill} in your agent to get started.`,
          );
        }
      },
    });

    track("cli_skills_add", {
      installed_count: installed.length,
      error_count: errors.length,
      all: installAll,
      agent: resolvedAgent ?? "unknown",
      output_format: json ? "json" : "text",
    });
  });
