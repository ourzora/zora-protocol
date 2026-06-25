import { Command } from "commander";
import { writeFileSync, mkdirSync } from "node:fs";
import { resolve, join } from "node:path";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { track } from "../lib/analytics.js";
import { SKILL_CONTENT } from "../generated/skill-content.js";
import {
  AGENT_HARNESS_ORDER,
  AGENT_HARNESS_SKILLS_DIRS,
  type AgentHarness,
  detectAgentHarness,
} from "../lib/agent-harness.js";

export type SkillMeta = {
  name: string;
  category: string;
  description: string;
};

// The core skill: the agent's full CLI interface. Every strategy skill depends on
// it (their instructions reference it), so installing any strategy skill also
// installs this one. Its content lives at the package root SKILL.md.
const CORE_SKILL_NAME = "cli";

// Grouped by category (Core → Onboarding → Discovery → Social → Risk → Reporting) so
// `skills list` and the docs present them in the same order. Skill content is bundled
// into the CLI (see src/generated/skill-content.ts) and installed from disk — there is
// no remote fetch, so the installed bytes are exactly the reviewed source at the commit
// this CLI was built from.
export const SKILLS: SkillMeta[] = [
  // Core
  {
    name: "cli",
    category: "Core",
    description:
      "The agent's full interface to Zora — set up an identity and trade, browse, look up coins, send tokens, and handle DMs from the CLI",
  },
  // Payments
  {
    name: "pay",
    category: "Payments",
    description:
      "Pay for x402-protected resources and APIs on Base — fetch-and-pay a URL or sign a payment for a 402 challenge",
  },
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

// Each skill installs as its own folder containing a SKILL.md:
//   <skills-dir>/zora-<name>/SKILL.md
// The folder name is what the harness uses as the command (e.g. /zora-onboarding),
// so the zora- prefix namespaces the install. Loose .md files and grouping subfolders
// are NOT discovered by Claude Code — one folder per skill, file named SKILL.md.
const SKILL_PREFIX = "zora-";

const getSkillContent = (name: string): string => {
  const content = SKILL_CONTENT[name];
  if (content === undefined) {
    throw new Error(
      `No bundled content for skill "${name}". This is a build error — ` +
        `run \`pnpm --filter @zoralabs/cli generate:skills\`.`,
    );
  }
  return content;
};

const writeSkill = (outDir: string, name: string): string => {
  const skillDir = join(outDir, `${SKILL_PREFIX}${name}`);
  mkdirSync(skillDir, { recursive: true });
  const outPath = join(skillDir, "SKILL.md");
  writeFileSync(outPath, getSkillContent(name));
  return outPath;
};

export const skillsCommand = new Command("skills")
  .description(
    "Install pre-built agent skills — onboarding plus discovery, social, risk, and reporting strategies (run `skills list` to see them all)",
  )
  .action(function (this: Command) {
    this.outputHelp();
  });

type PublicSkillMeta = SkillMeta;

const getPublicSkills = (): PublicSkillMeta[] => SKILLS;

skillsCommand
  .command("list")
  .description("List available skills")
  .action(function (this: Command) {
    const json = getJson(this);
    outputData(json, {
      json: { skills: getPublicSkills() },
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
    const agentFlag = opts.agent as AgentHarness | undefined;
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
    let resolvedAgent: AgentHarness | "custom" | null = null;
    if (dirFlag) {
      outDir = resolve(dirFlag);
      resolvedAgent = "custom";
    } else if (agentFlag) {
      if (!AGENT_HARNESS_SKILLS_DIRS[agentFlag]) {
        return outputErrorAndExit(
          json,
          `Unknown agent: ${agentFlag}`,
          `Supported: ${AGENT_HARNESS_ORDER.join(", ")}`,
        );
      }
      outDir = resolve(process.cwd(), AGENT_HARNESS_SKILLS_DIRS[agentFlag]);
      resolvedAgent = agentFlag;
    } else {
      const detected = detectAgentHarness(process.cwd());
      resolvedAgent = detected ?? "claude";
      outDir = resolve(process.cwd(), AGENT_HARNESS_SKILLS_DIRS[resolvedAgent]);
    }

    const requested = installAll ? SKILLS.map((s) => s.name) : [name!];
    const invalid = requested.filter((n) => !SKILLS.some((s) => s.name === n));
    if (invalid.length > 0) {
      return outputErrorAndExit(
        json,
        `Unknown skill: ${invalid.join(", ")}`,
        `Available: ${SKILLS.map((s) => s.name).join(", ")}`,
      );
    }

    // Every strategy skill depends on the core CLI skill, so make sure it is
    // installed alongside. This also removes the need for skills to pull the core
    // skill from the network at runtime.
    const toInstall = new Set(requested);
    // Only auto-add the core skill when a strategy skill is being installed and
    // the core skill wasn't already requested (so `skills add cli` stays a no-op here).
    const coreAddedAsDep =
      requested.some((n) => n !== CORE_SKILL_NAME) &&
      !toInstall.has(CORE_SKILL_NAME);
    if (coreAddedAsDep) toInstall.add(CORE_SKILL_NAME);

    mkdirSync(outDir, { recursive: true });

    const installed: { name: string; path: string }[] = [];
    const errors: { name: string; error: string }[] = [];

    for (const skillName of toInstall) {
      try {
        const outPath = writeSkill(outDir, skillName);
        installed.push({ name: `${SKILL_PREFIX}${skillName}`, path: outPath });
      } catch (err) {
        errors.push({
          name: skillName,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    if (errors.length > 0 && installed.length === 0) {
      return outputErrorAndExit(
        json,
        `Failed to install: ${errors.map((e) => e.name).join(", ")}`,
        errors[0]!.error,
      );
    }

    outputData(json, {
      json: {
        installed,
        errors: errors.length > 0 ? errors : undefined,
        agent: resolvedAgent,
        dir: outDir,
        coreSkillInstalled: coreAddedAsDep,
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
        if (coreAddedAsDep) {
          console.log(
            `\x1b[2m  (also installed ${SKILL_PREFIX}${CORE_SKILL_NAME}, the core skill these depend on)\x1b[0m`,
          );
        }
        const firstRequested = requested[0];
        if (firstRequested) {
          console.log(
            `\nInvoke by typing /${SKILL_PREFIX}${firstRequested} in your agent to get started.`,
          );
        }
      },
    });

    track("cli_skills_add", {
      installed_count: installed.length,
      error_count: errors.length,
      core_skill_installed: coreAddedAsDep,
      all: installAll,
      agent: resolvedAgent ?? "unknown",
      output_format: json ? "json" : "text",
    });

    if (errors.length > 0) process.exit(1);
  });
