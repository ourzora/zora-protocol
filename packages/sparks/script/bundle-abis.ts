import { promises as fs } from "fs";
import { basename, extname, join, resolve } from "pathe";
import { glob } from "glob";
import { ContractConfig } from "@wagmi/cli";

const defaultExcludes = [
  "Common.sol/**",
  "Components.sol/**",
  "Script.sol/**",
  "StdAssertions.sol/**",
  "StdInvariant.sol/**",
  "StdError.sol/**",
  "StdCheats.sol/**",
  "StdMath.sol/**",
  "StdJson.sol/**",
  "StdStorage.sol/**",
  "StdUtils.sol/**",
  "Vm.sol/**",
  "console.sol/**",
  "console2.sol/**",
  "test.sol/**",
  "**.s.sol/*.json",
  "**.t.sol/*.json",
];

// design inspired by https://github.com/wagmi-dev/wagmi/blob/main/packages/cli/src/plugins/foundry.ts

export const readContracts = async ({
  deployments = {} as any,
  exclude = defaultExcludes,
  include = ["*.json"],
  namePrefix = "",
  project_ = "./",
}) => {
  // get all the files in ./out
  function getContractName(artifactPath: string, usePrefix = true) {
    const filename = basename(artifactPath);
    const extension = extname(artifactPath);
    return `${usePrefix ? namePrefix : ""}${filename.replace(extension, "")}`;
  }

  async function getContract(artifactPath: string) {
    const artifact = JSON.parse(await fs.readFile(artifactPath, "utf-8"));
    return {
      abi: artifact.abi,
      address: (deployments as Record<string, ContractConfig["address"]>)[
        getContractName(artifactPath, false)
      ],
      name: getContractName(artifactPath),
    };
  }

  async function getArtifactPaths(artifactsDirectory: string) {
    return await glob([
      ...include.map((x) => `${artifactsDirectory}/**/${x}`),
      ...exclude.map((x) => `!${artifactsDirectory}/**/${x}`),
    ]);
  }

  const project = resolve(process.cwd(), project_ ?? "");

  const config = {
    out: "out",
    src: "src",
  };

  const artifactsDirectory = join(project, config.out);

  const artifactPaths = await getArtifactPaths(artifactsDirectory);
  const contracts = [];
  for (const artifactPath of artifactPaths) {
    const contract = await getContract(artifactPath);
    if (!contract.abi?.length) continue;
    contracts.push(contract);
  }
  return contracts;
};

async function saveContractsAbisJson(contracts: { abi: any; name: string }[]) {
  // for each contract, write abi to ./abis/{contractName}.json

  const abisFolder = "./abis";

  // mkdir - p ./abis:
  await fs.mkdir(abisFolder, { recursive: true });
  // remove abis folder:
  await fs.rm(abisFolder, { recursive: true });
  // add it back
  // mkdir - p ./abis:
  await fs.mkdir(abisFolder, { recursive: true });

  // now write abis:
  await Promise.all(
    contracts.map(async (contract) => {
      const abiJson = JSON.stringify(contract.abi, null, 2);
      const abiJsonPath = `${abisFolder}/${contract.name}.json`;

      await fs.writeFile(abiJsonPath, abiJson);
    }),
  );
}

async function main() {
  const contracts = await readContracts({});

  await saveContractsAbisJson(contracts);
}

main();
