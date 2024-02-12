import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";

// Reads all the chain configs in ./chainConfigs folder, and bundles them into a typescript
// definition that looks like:
// export const chainConfigs = {
//  [chainId]: {
//    ...chainConfig
//  }
//}

const readConfigs = async ({
  folder,
  configType,
}: {
  folder: string;
  configType: "chainConfigs" | "addresses";
}) => {
  const files = readdirSync(folder).map((fileName) => ({
    fileName,
    path: join(folder, fileName),
  }));

  const allConfigs: Record<string, any> = Object.fromEntries(
    await Promise.all(
      files.map(async ({ fileName, path }) => {
        const chainId = fileName.split(".")[0]!;
        const fileContents = JSON.parse(readFileSync(path, "utf-8"));

        return [chainId, fileContents];
      }),
    ),
  );

  return {
    configType,
    configs: allConfigs,
  };
};

function writeConfigsToJsFile({
  mergedConfigs,
  packageName,
}: {
  mergedConfigs: Record<string, any>;
  packageName: string;
}) {
  // combine them into a single mapping
  const configCode = Object.entries(mergedConfigs)
    .map(([configType, configs]) => {
      return `export const ${configType} = ${JSON.stringify(
        configs,
        null,
        2,
      )};`;
    })
    .join("\n");

  writeFileSync(`./src/generated/${packageName}.ts`, configCode);
}

async function mergeAndSaveConfigs({
  configs,
  packageName,
}: {
  configs: {
    folder: string;
    configType: "chainConfigs" | "addresses";
  }[];
  packageName: string;
}) {
  // read all config files in the target folder
  const allConfigs = await Promise.all(configs.map(readConfigs));

  const mergedConfigs: Record<string, any> = {};

  allConfigs.forEach(({ configType, configs }) => {
    mergedConfigs[configType] = configs;
  });

  // convert above to typescript code string:
  writeConfigsToJsFile({ mergedConfigs, packageName });

  // save output to json file
  const jsonFile = `./json/${packageName}.json`;
  writeFileSync(jsonFile, JSON.stringify(mergedConfigs, null, 2));
}

async function bundleChainConfigs() {
  // ensure the directories are there
  mkdirSync("./src/generated", { recursive: true });
  mkdirSync("./json", { recursive: true });

  await mergeAndSaveConfigs({
    configs: [
      {
        folder: "../1155-deployments/chainConfigs",
        configType: "chainConfigs",
      },
      {
        folder: "../1155-deployments/addresses",
        configType: "addresses",
      },
    ],
    packageName: "1155",
  });
}

await bundleChainConfigs();
