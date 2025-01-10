import { readFile, writeFile } from "fs/promises";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function copyChangelog(
  sourceChangelogPath: string,
  destinationChangelogPath: string,
  packageName: string,
) {
  const changelog = await readFile(sourceChangelogPath, "utf8");

  // Delete first line and join the rest
  const lines = changelog.split("\n");
  let newChangelog = lines.slice(1).join("\n");

  // Insert the new title
  newChangelog = `# ${packageName} Changelog\n\n${newChangelog}`;

  // Replace commit hashes with links to GitHub commits
  newChangelog = newChangelog.replace(
    /\[([0-9a-f]{8})\]/g,
    "[$1](https://github.com/ourzora/zora-protocol/commit/$1)",
  );

  // Add links to commit hashes in changelog entries
  newChangelog = newChangelog.replace(
    /^- ([0-9a-f]{8}):/gm,
    "- [$1](https://github.com/ourzora/zora-protocol/commit/$1):",
  );

  await writeFile(destinationChangelogPath, newChangelog, "utf8");
}

async function main() {
  await copyChangelog(
    join(__dirname, "../../packages/protocol-sdk/CHANGELOG.md"),
    join(__dirname, "../pages/changelogs/protocol-sdk.mdx"),
    "@zoralabs/protocol-sdk",
  );

  await copyChangelog(
    join(__dirname, "../../packages/protocol-deployments/CHANGELOG.md"),
    join(__dirname, "../pages/changelogs/protocol-deployments.mdx"),
    "@zoralabs/protocol-deployments",
  );

  await copyChangelog(
    join(__dirname, "../../packages/1155-contracts/CHANGELOG.md"),
    join(__dirname, "../pages/changelogs/1155-contracts.mdx"),
    "Zora 1155 Contracts",
  );

  await copyChangelog(
    join(__dirname, "../../packages/cointags/CHANGELOG.md"),
    join(__dirname, "../pages/changelogs/cointags.mdx"),
    "Cointags",
  );
}

main();
