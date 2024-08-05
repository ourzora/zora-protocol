import { fileURLToPath } from "url";
import { dirname, join } from "path";
import handlebars from "handlebars";
import { readFile, writeFile, mkdir } from "fs/promises";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// fork tests will be code generated for each chain
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
  // "blast_sepolia",
];

type ForkTestGenConfig = {
  // for the given fork test, the chains to run the fork tests on.  A test will be generated for each fork.
  forks: string[];
  // the base test class for the generated test to inherit from
  baseTestClass: string;
  // the function from the base class to call
  baseTestFunction: string;
  // the output file name for the generated test
  outputTestFile: string;
};

const forkTestGenConfigs: ForkTestGenConfig[] = [
  {
    forks: forkTestChains,
    baseTestClass: "UpgradesTestBase",
    baseTestFunction: "simulateUpgrade",
    outputTestFile: "UpgradesTest",
  },
  {
    forks: forkTestChains,
    baseTestClass: "ZoraCreator1155FactoryBase",
    baseTestFunction: "canCreateContractAndMint",
    outputTestFile: "ZoraCreator1155FactoryTest",
  },
  {
    forks: ["zora"],
    baseTestClass: "ZoraCreator1155PremintExecutorBase",
    baseTestFunction: "legacyPremint_successfullyMintsPremintTokens",
    outputTestFile: "ZoraCreator1155PremintExecutorLegacy",
  },
  {
    forks: ["zora"],
    baseTestClass: "ZoraCreator1155PremintExecutorBase",
    baseTestFunction: "premintV1_successfullyMintsPremintTokens",
    outputTestFile: "ZoraCreator1155PremintExecutorPremintV1",
  },
  {
    forks: forkTestChains,
    baseTestClass: "ZoraCreator1155PremintExecutorBase",
    baseTestFunction: "premintV2_successfullyMintsPremintTokens",
    outputTestFile: "ZoraCreator1155PremintExecutorPremintV2",
  },
];

function gitignoreGeneratedFiles(files: string[]) {
  const ignorePaths = files.map((f) => `${f}.t.sol`).join("\n");

  const gitignorePath = join(__dirname, "../test/.gitignore");

  return writeFile(gitignorePath, ignorePaths);
}

const generatedBaseDir = join(__dirname, "../test/generated/");

const generateForTests = async (config: ForkTestGenConfig) => {
  const templatePath = join(__dirname, "../templates/ForkTests.template.sol");

  const templateSource = await readFile(templatePath, "utf-8");
  const template = handlebars.compile(templateSource);

  const result = template(config);

  const destination = join(generatedBaseDir, `${config.outputTestFile}.t.sol`);

  await writeFile(destination, result);
};

const generateAllForkTests = async () => {
  // make the generatedBaseDir directory if it doesnt exist:
  await mkdir(generatedBaseDir, { recursive: true });

  for (const config of forkTestGenConfigs) {
    await generateForTests(config);
  }

  await gitignoreGeneratedFiles(
    forkTestGenConfigs.map((c) => c.outputTestFile),
  );
};

generateAllForkTests();
