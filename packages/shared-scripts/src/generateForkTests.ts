#!/usr/bin/env tsx
import { join } from "pathe";
import handlebars from "handlebars";
import { promises as fs } from "fs";

// Fork tests will be code generated for each chain
const forkTestChains = [
  "mainnet",
  "optimism",
  "zora",
  "sepolia",
  "base",
  "base_sepolia",
  "zora_sepolia",
  "arbitrum_one",
  "arbitrum_sepolia",
  "blast",
];

type ForkTestGenConfig = {
  forks: string[];
  baseTestClass: string;
  baseTestFunction: string;
  outputTestFile: string;
};

const forkTestGenConfigs: ForkTestGenConfig[] = [
  {
    forks: forkTestChains,
    baseTestClass: "UpgradesTestBase",
    baseTestFunction: "simulateUpgrade",
    outputTestFile: "UpgradesTest",
  },
];

async function gitignoreGeneratedFiles(projectPath: string, files: string[]) {
  const ignorePaths = files.map((f) => `${f}.t.sol`).join("\n");
  const gitignorePath = join(projectPath, "test/.gitignore");
  await fs.writeFile(gitignorePath, ignorePaths);
}

async function generateForTests(
  projectPath: string,
  config: ForkTestGenConfig,
) {
  const templatePath = join(projectPath, "templates/ForkTests.template.sol");
  const templateSource = await fs.readFile(templatePath, "utf-8");
  const template = handlebars.compile(templateSource);
  const result = template(config);
  const generatedBaseDir = join(projectPath, "test/generated/");
  await fs.mkdir(generatedBaseDir, { recursive: true });
  const destination = join(generatedBaseDir, `${config.outputTestFile}.t.sol`);
  await fs.writeFile(destination, result);
}

export const generateAllForkTests = async (
  projectPath: string = process.cwd(),
) => {
  for (const config of forkTestGenConfigs) {
    await generateForTests(projectPath, config);
  }

  await gitignoreGeneratedFiles(
    projectPath,
    forkTestGenConfigs.map((c) => c.outputTestFile),
  );
};

const isMainModule = import.meta.url.startsWith("file:");
if (isMainModule) {
  generateAllForkTests().catch(console.error);
}
