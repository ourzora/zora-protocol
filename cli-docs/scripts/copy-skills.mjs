import { mkdir, cp } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..");
const cliPkg = resolve(repoRoot, "packages/cli");
const skillsSrc = resolve(cliPkg, "skills");
const publicDir = resolve(__dirname, "..", "docs/public");
const skillDest = resolve(publicDir, "skill");

const SKILLS = [
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
];

await mkdir(skillDest, { recursive: true });

// Copy the CLI agent reference (SKILL.md → /skill.md). Also serve it under the
// /skill/<name>.md convention as /skill/cli.md so `zora skills add cli` can fetch
// it the same way as the strategy skills below.
await cp(resolve(cliPkg, "SKILL.md"), resolve(publicDir, "skill.md"));
await cp(resolve(cliPkg, "SKILL.md"), resolve(skillDest, "cli.md"));

// Copy each skill to /skill/<name>.md
for (const name of SKILLS) {
  const src = resolve(skillsSrc, name, "SKILL.md");
  const dest = resolve(skillDest, `${name}.md`);
  await cp(src, dest);
}

console.log(
  `Copied CLI SKILL.md + ${SKILLS.length} agent skills to ${publicDir}`,
);
