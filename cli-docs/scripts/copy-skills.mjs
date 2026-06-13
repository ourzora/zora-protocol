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
  "onboarding",
  "copy-trader",
  "early-buyer",
  "watchlist",
  "take-profit",
];

await mkdir(skillDest, { recursive: true });

// Copy the CLI agent reference (SKILL.md → /skill.md)
await cp(resolve(cliPkg, "SKILL.md"), resolve(publicDir, "skill.md"));

// Copy each skill to /skill/<name>.md
for (const name of SKILLS) {
  const src = resolve(skillsSrc, name, "SKILL.md");
  const dest = resolve(skillDest, `${name}.md`);
  await cp(src, dest);
}

console.log(
  `Copied CLI SKILL.md + ${SKILLS.length} agent skills to ${publicDir}`,
);
