import { Command } from "commander";
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { track } from "../lib/analytics.js";

const DEFAULT_SKILLS_BASE_URL = "https://agents.zora.com/skill";

const getSkillsBaseUrl = (): string =>
  process.env.ZORA_SKILLS_BASE_URL || DEFAULT_SKILLS_BASE_URL;

type SkillMeta = {
  name: string;
  category: string;
  description: string;
};

// Grouped by category (Onboarding → Discovery → Social → Risk → Reporting) so
// `skills list` and the docs present them in the same order.
const SKILLS: SkillMeta[] = [
  // Onboarding
  {
    name: "onboarding",
    category: "Onboarding",
    description:
      "Set up on Zora for the first time — publish your profile, create your smart wallet and creator coin, and post your first meme",
  },
  // Discovery
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
    name: "trend-sniper",
    category: "Discovery",
    description:
      "Watch the global trending feed and snipe new trend coins on appearance or a volume spike",
  },
  {
    name: "new-coin-screener",
    category: "Discovery",
    description:
      "Poll the global new-coin feed and auto-buy launches that pass a market-cap/holder screen",
  },
  {
    name: "whale-watcher",
    category: "Discovery",
    description:
      "Watch top holders and large trades on chosen coins, then alert or auto-trade on whale moves",
  },
  // Social
  {
    name: "copy-trader",
    category: "Social",
    description:
      "Mirror another user's trades — existing holdings, future trades, or both",
  },
  {
    name: "dm-responder",
    category: "Social",
    description:
      "Auto-triage and respond to DMs — approve/deny requests, greet new conversations, and flag keyword matches by rule",
  },
  {
    name: "comment-engager",
    category: "Social",
    description:
      "Read and reply to comments on coins you hold, in your own voice, to build social presence",
  },
  {
    name: "social-trader",
    category: "Social",
    description:
      "Follow specific creators and buy their new post coins or growing creator coins",
  },
  {
    name: "auto-poster",
    category: "Social",
    description:
      "Publish a new post on a schedule to keep your agent active and in-character",
  },
  // Risk
  {
    name: "take-profit",
    category: "Risk",
    description:
      "Auto-sell positions at configured take-profit or stop-loss price targets",
  },
  {
    name: "dca",
    category: "Risk",
    description:
      "Dollar-cost-average a fixed amount into chosen coins each iteration, with budget caps",
  },
  {
    name: "portfolio-rebalancer",
    category: "Risk",
    description:
      "Rebalance holdings back to target allocations when they drift past a tolerance band",
  },
  // Reporting
  {
    name: "portfolio-digest",
    category: "Reporting",
    description:
      "Read-only periodic portfolio and PnL digest, optionally delivered to the operator by DM",
  },
];

type Agent = "claude" | "cursor" | "windsurf" | "openclaw" | "hermes";

const AGENT_ORDER: Agent[] = [
  "claude",
  "cursor",
  "windsurf",
  "openclaw",
  "hermes",
];

// Each skill installs as its own folder containing a SKILL.md:
//   <skills-dir>/zora-<name>/SKILL.md
// The folder name is what the harness uses as the command (e.g. /zora-onboarding),
// so the zora- prefix namespaces the install. Loose .md files and grouping subfolders
// are NOT discovered by Claude Code — one folder per skill, file named SKILL.md.
const SKILL_PREFIX = "zora-";

const AGENT_SKILLS_DIRS: Record<Agent, string> = {
  claude: ".claude/skills",
  cursor: ".cursor/skills",
  windsurf: ".windsurf/skills",
  openclaw: ".openclaw/skills",
  hermes: ".hermes/skills",
};

const AGENT_ROOT_DIRS: Record<Agent, string> = {
  claude: ".claude",
  cursor: ".cursor",
  windsurf: ".windsurf",
  openclaw: ".openclaw",
  hermes: ".hermes",
};

const detectAgent = (cwd: string): Agent | null => {
  for (const agent of AGENT_ORDER) {
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
    "Install pre-built agent skills — onboarding plus discovery, social, risk, and reporting strategies (run `skills list` to see them all)",
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
          console.log(`  ${s.name.padEnd(16)} ${s.description}`);
        }
        console.log("\nInstall with: zora skills add <name>");
      },
    });
    track("cli_skills_list", { output_format: json ? "json" : "text" });
  });

skillsCommand
  .command("add [name]")
  .description(
    "Install a skill into your agent's skills directory (auto-detects .claude, .cursor, .windsurf, .openclaw, .hermes)",
  )
  .option("--all", "Install all skills")
  .option(
    "--agent <agent>",
    "Target agent: claude, cursor, windsurf, openclaw, hermes (default: auto-detect)",
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
      if (!AGENT_SKILLS_DIRS[agentFlag]) {
        return outputErrorAndExit(
          json,
          `Unknown agent: ${agentFlag}`,
          `Supported: ${AGENT_ORDER.join(", ")}`,
        );
      }
      outDir = resolve(process.cwd(), AGENT_SKILLS_DIRS[agentFlag]);
      resolvedAgent = agentFlag;
    } else {
      const detected = detectAgent(process.cwd());
      resolvedAgent = detected ?? "claude";
      outDir = resolve(process.cwd(), AGENT_SKILLS_DIRS[resolvedAgent]);
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

    for (const file of names) {
      try {
        const content = await fetchSkill(file);
        const skillDir = join(outDir, `${SKILL_PREFIX}${file}`);
        mkdirSync(skillDir, { recursive: true });
        const outPath = join(skillDir, "SKILL.md");
        writeFileSync(outPath, content);
        installed.push({ name: `${SKILL_PREFIX}${file}`, path: outPath });
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
        if (installed.length > 0) {
          const firstSkill = installed[0]!.name;
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
