/**
 * Generates SHA-256 integrity hashes for all skills.
 *
 * Usage:
 *   npx tsx scripts/generate-skill-hashes.ts          # Print hashes to console
 *   npx tsx scripts/generate-skill-hashes.ts --write  # Update skills.ts directly
 *   npx tsx scripts/generate-skill-hashes.ts --check  # Check if hashes are up-to-date (CI)
 */

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILLS_TS_PATH = join(__dirname, "../src/commands/skills.ts");

const SKILLS_URL = "https://agents.zora.com/skill";

const computeIntegrity = (content: string): string => {
  const hash = createHash("sha256").update(content, "utf8").digest("base64");
  return `sha256-${hash}`;
};

/**
 * Parse skill names from skills.ts to avoid import dependency chain.
 * Single source of truth - names are extracted from the SKILLS array.
 */
function parseSkillNamesFromFile(): string[] {
  const content = readFileSync(SKILLS_TS_PATH, "utf8");
  const names: string[] = [];

  // Match all name: "skillname" patterns within the SKILLS array
  const namePattern = /name:\s*"([^"]+)"/g;
  let match;
  while ((match = namePattern.exec(content)) !== null) {
    names.push(match[1]);
  }

  if (names.length === 0) {
    throw new Error("No skill names found in skills.ts");
  }

  return names;
}

/**
 * Parse current hashes from skills.ts
 */
function getCurrentHashes(): Map<string, string> {
  const content = readFileSync(SKILLS_TS_PATH, "utf8");
  const hashes = new Map<string, string>();
  const skillNames = parseSkillNamesFromFile();

  for (const name of skillNames) {
    // Use lazy matching to find the integrity field for each skill
    const pattern = new RegExp(
      `name:\\s*"${name}"[\\s\\S]*?integrity:\\s*"([^"]*)"`,
    );
    const match = content.match(pattern);
    if (match) {
      hashes.set(name, match[1]);
    }
  }

  return hashes;
}

async function fetchAllHashes(): Promise<Map<string, string>> {
  const hashes = new Map<string, string>();
  const skillNames = parseSkillNamesFromFile();

  for (const name of skillNames) {
    const url = `${SKILLS_URL}/${name}.md`;
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${name}: HTTP ${response.status}`);
    }
    const content = await response.text();
    hashes.set(name, computeIntegrity(content));
  }

  return hashes;
}

function updateSkillsFile(hashes: Map<string, string>): boolean {
  const content = readFileSync(SKILLS_TS_PATH, "utf8");
  let updated = content;
  let changed = false;
  const errors: string[] = [];

  for (const [name, hash] of hashes) {
    // First, verify this skill has an integrity field by checking
    // that we can find it within its own object block (before the next skill)
    // Find the position of this skill's name
    const namePattern = new RegExp(`name:\\s*"${name}"`);
    const nameMatch = namePattern.exec(updated);
    if (!nameMatch) {
      errors.push(`Skill "${name}" not found in skills.ts`);
      continue;
    }

    const namePos = nameMatch.index;

    // Find the next skill's name (if any) to bound our search
    const remainingContent = updated.slice(namePos + nameMatch[0].length);
    const nextSkillMatch = /name:\s*"[^"]+"/.exec(remainingContent);
    const searchBound = nextSkillMatch
      ? namePos + nameMatch[0].length + nextSkillMatch.index
      : updated.length;

    // Extract the bounded region for this skill
    const skillRegion = updated.slice(namePos, searchBound);

    // Check if integrity field exists in this skill's region
    const integrityInRegion = /integrity:\s*"[^"]*"/.exec(skillRegion);
    if (!integrityInRegion) {
      errors.push(
        `Skill "${name}" is missing integrity field - add 'integrity: "sha256-PLACEHOLDER"' to the skill definition`,
      );
      continue;
    }

    // Now safely replace the integrity value within the bounded region
    const updatedRegion = skillRegion.replace(
      /(integrity:\s*)"[^"]*"/,
      `$1"${hash}"`,
    );

    if (updatedRegion !== skillRegion) {
      changed = true;
      updated = updated.slice(0, namePos) + updatedRegion + updated.slice(searchBound);
    }
  }

  if (errors.length > 0) {
    console.error("\nErrors found:");
    for (const err of errors) {
      console.error(`  - ${err}`);
    }
    process.exit(1);
  }

  if (changed) {
    writeFileSync(SKILLS_TS_PATH, updated);
  }

  return changed;
}

async function main() {
  const args = process.argv.slice(2);
  const writeMode = args.includes("--write");
  const checkMode = args.includes("--check");

  console.log("Fetching skills from production...\n");

  let remoteHashes: Map<string, string>;
  try {
    remoteHashes = await fetchAllHashes();
  } catch (err) {
    console.error("Failed to fetch skills:", err);
    process.exit(1);
  }

  if (checkMode) {
    const currentHashes = getCurrentHashes();
    let hasChanges = false;

    for (const [name, remoteHash] of remoteHashes) {
      const currentHash = currentHashes.get(name);
      if (currentHash !== remoteHash) {
        console.log(`${name}: CHANGED`);
        console.log(`  Current:  ${currentHash}`);
        console.log(`  Expected: ${remoteHash}\n`);
        hasChanges = true;
      }
    }

    if (hasChanges) {
      console.log("Skill hashes are out of date. Run with --write to update.");
      process.exit(1);
    } else {
      console.log("All skill hashes are up to date.");
      process.exit(0);
    }
  }

  if (writeMode) {
    const changed = updateSkillsFile(remoteHashes);
    if (changed) {
      console.log("Updated skills.ts with new hashes:");
      for (const [name, hash] of remoteHashes) {
        console.log(`  ${name}: ${hash}`);
      }
    } else {
      console.log("No changes needed - hashes are already up to date.");
    }
  } else {
    console.log("Generated hashes (run with --write to update skills.ts):\n");
    for (const [name, hash] of remoteHashes) {
      console.log(`  ${name}: ${hash}`);
    }
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
