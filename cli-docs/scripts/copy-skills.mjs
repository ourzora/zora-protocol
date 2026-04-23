import { readFile, writeFile, mkdir, cp } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..", "..");
const cliPkg = resolve(repoRoot, "packages/cli");
const skillsSrc = resolve(cliPkg, "skills");
const publicDir = resolve(__dirname, "..", "docs/public");
const skillDest = resolve(publicDir, "skill");

const SKILLS = ["copy-trader", "early-buyer", "watchlist", "take-profit"];

await mkdir(skillDest, { recursive: true });

// Copy the CLI agent reference (SKILL.md → /skill.md)
await cp(resolve(cliPkg, "SKILL.md"), resolve(publicDir, "skill.md"));

// Copy and link-rewrite each skill
for (const name of SKILLS) {
  const src = resolve(skillsSrc, name, "SKILL.md");
  const dest = resolve(skillDest, `${name}.md`);
  const content = await readFile(src, "utf8");
  // Skills reference `../_shared/cli-setup.md`. After flattening to /skill/<name>.md,
  // cli-setup lives at /skill/cli-setup.md — rewrite the link so it still resolves.
  const rewritten = content.replaceAll(
    "../_shared/cli-setup.md",
    "./cli-setup.md",
  );
  await writeFile(dest, rewritten);
}

// Copy the shared cli-setup reference alongside the skills
await cp(
  resolve(skillsSrc, "_shared/cli-setup.md"),
  resolve(skillDest, "cli-setup.md"),
);

console.log(
  `Copied CLI SKILL.md + ${SKILLS.length} agent skills + cli-setup to ${publicDir}`,
);
