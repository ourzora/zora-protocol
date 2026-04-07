#!/usr/bin/env tsx
import { join as systemJoin, normalize as systemNormalize } from "path";
import handlebars from "handlebars";
import { readFile, mkdir, writeFile } from "fs/promises";

const chainIdentifierToName = {
  "8543": "base",
  "7777777": "zora",
  zora: "zora",
  base: "base",
};

interface CoinEntry {
  coin: string;
  contractAddress: string;
  poolAddress: string;
  chainName: string;
  version: string;
}

function join(basePath: string, relativePath: string): string {
  const joinedPath = systemJoin(basePath, relativePath);
  return systemNormalize(joinedPath);
}

function parseCoinsTSVFile(input: string): CoinEntry[] {
  const lines = input.split("\n");
  const headers = lines[0].split("\t");

  const requiredFields = ["coin", "ca", "pool", "chain", "uniswap_version"];
  const fieldIndexes = {
    coin: headers.indexOf("coin"),
    ca: headers.indexOf("ca"),
    pool: headers.indexOf("pool"),
    chain: headers.indexOf("chain"),
    uniswap_version: headers.indexOf("uniswap_version"),
  };

  if (requiredFields.some((field) => fieldIndexes[field] === -1)) {
    throw new Error("Input file is missing required fields");
  }

  return lines.slice(1).reduce((acc, line) => {
    const values = line.split("\t");

    // Check if required fields are filled out
    if (
      requiredFields.filter((field) => !!values[fieldIndexes[field]]?.trim())
        .length === requiredFields.length
    ) {
      acc.push({
        coin: values[fieldIndexes.coin]?.trim() || "",
        contractAddress: values[fieldIndexes.ca]?.trim() || "",
        poolAddress: values[fieldIndexes.pool]?.trim() || "",
        version: values[fieldIndexes.uniswap_version]?.trim(),
        chainName: chainIdentifierToName[values[fieldIndexes.chain]?.trim()],
      });
    }

    return acc;
  }, [] as CoinEntry[]);
}

async function gitignoreGeneratedFiles(projectPath: string, files: string[]) {
  const ignorePaths = files.join("\n");
  const gitignorePath = join(projectPath, "/.gitignore");
  await writeFile(gitignorePath, ignorePaths);
}

async function generateTokenForkTests(projectPath: string, coins: CoinEntry[]) {
  const templatePath = join(projectPath, "test/integration/generator/ForkTests.sol.template");
  const templateSource = await readFile(templatePath, "utf-8");
  const template = handlebars.compile(templateSource);
  const result = template({ coins });
  const generatedBaseDir = join(projectPath, "test/integration/generated/");
  await mkdir(generatedBaseDir, { recursive: true });
  const resultFilename = 'Coins.t.sol';
  const destination = join(generatedBaseDir, resultFilename);
  await writeFile(destination, result);
  return `test/integration/generated/${resultFilename}`;
}

export const generateAllForkTests = async (
  projectPath: string = process.cwd(),
) => {
  const configs = parseCoinsTSVFile(
    await readFile(join(projectPath, "test/integration/generator/coins-test-config.tsv"), "utf-8"),
  );

  const outputFile = await generateTokenForkTests(projectPath, configs);

  await gitignoreGeneratedFiles(projectPath, [outputFile]);
};

const isMainModule = import.meta.url.startsWith("file:");
if (isMainModule) {
  generateAllForkTests().catch(console.error);
}
