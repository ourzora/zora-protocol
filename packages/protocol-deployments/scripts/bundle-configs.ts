import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import * as prettier from "prettier";

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

  const allConfigs: [number, any][] = await Promise.all(
    files.map(async ({ fileName, path }) => {
      const chainId = fileName.split(".")[0]!;
      const fileContents = JSON.parse(readFileSync(path, "utf-8"));

      return [+chainId, fileContents];
    }),
  );

  const mergedConfigs: Record<number, any> = {};

  allConfigs.forEach(([chainId, config]) => {
    mergedConfigs[chainId] = config;
  });

  return {
    configType,
    configs: mergedConfigs,
  };
};

function customStringify(obj: any) {
  let isArray = Array.isArray(obj);
  return (
    (isArray ? "[" : "{") +
    Object.entries(obj)
      .map(([key, value]) => {
        let val: any =
          typeof value === "object"
            ? customStringify(value)
            : JSON.stringify(value);
        return isArray ? val : `${key}:${val}`;
      })
      .join(",") +
    (isArray ? "]" : "}")
  );
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

  const configCode = allConfigs
    .map(({ configType, configs }) => {
      return `export const ${configType} = ${customStringify(configs)};`;
    })
    .join("\n");

  writeFileSync(
    `./src/generated/${packageName}.ts`,
    await prettier.format(configCode, { parser: "typescript" }),
  );
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

  await mergeAndSaveConfigs({
    configs: [
      {
        folder: "../mints-deployments/chainConfigs",
        configType: "chainConfigs",
      },
      {
        folder: "../mints-deployments/addresses",
        configType: "addresses",
      },
    ],
    packageName: "mints",
  });
}

await bundleChainConfigs();
