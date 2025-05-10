import { writeFile, readFile } from "fs/promises";
import esMain from "es-main";
// @ts-ignore
import { glob } from "glob";
// @ts-ignore
import semverGt from "semver/functions/gt";

type Deploy = {
  timestamp: number;
  commit: string;
  returns: { value: string }[];
  chain: number;
};

async function copyEnvironmentRunFiles() {
  const latestFiles = await glob(`broadcast/**/*run-latest.json`);

  const allFileContents = await Promise.all(
    latestFiles.map(async (file: string) => {
      const fileParts = file.split("/");
      const chainId = fileParts[fileParts.length - 2];
      const parsed = JSON.parse(await readFile(file, "utf-8")) as Deploy;
      const returns = parsed.returns[0]?.value || "{}";

      // A recent version of forge added a bug where the returns value had URL-based encoding.
      // The code below is a hack to fix this. It should be removed once forge is fixed.
      // Remove all instances of '\' from returns and fix improperly placed quotes.
      const filtered = returns
        .replace(/\\/g, "")
        .replace('"{', "{")
        .replace('}"', "}");

      const parsedReturns = JSON.parse(filtered);
      return {
        chainId,
        timestamp: parsed.timestamp,
        returns: parsedReturns,
      };
    })
  );

  const groupedByChainId = allFileContents.reduce((acc: any, file: any) => {
    const chainId = file.chainId;
    if (isNaN(Number(chainId))) return acc;
    if (!acc[chainId]) {
      acc[chainId] = [];
    }
    acc[chainId].push(file);
    return acc;
  }, {} as Record<string, Deploy[]>);

  const withLatest = Object.entries(groupedByChainId).map(
    ([chainId, files]) => {
      const latest = files.sort(
        (a, b) => b.timestamp - a.timestamp
      )[0];
      return { chainId, latest };
    }
  );

  for (const { chainId, latest } of withLatest) {
    const filePath = `addresses/${chainId}.json`;
    let shouldWrite = true;
    try {
      const fileResponse = await readFile(filePath);
      if (fileResponse) {
        const version = JSON.parse(fileResponse.toString("utf-8"));
        if (
          semverGt(
            version.CONTRACT_1155_IMPL_VERSION,
            latest.returns.CONTRACT_1155_IMPL_VERSION
          )
        ) {
          console.log(
            `skipping since ${version.CONTRACT_1155_IMPL_VERSION} is newer than deploy files (${latest.returns.CONTRACT_1155_IMPL_VERSION})`
          );
          shouldWrite = false;
        }
      }
    } catch (error) {
      // File doesn't exist; we will write the file.
    }
    if (shouldWrite) {
      await writeFile(
        filePath,
        JSON.stringify(
          {
            ...latest.returns,
            timestamp: latest.timestamp,
            commit: latest.commit,
          },
          null,
          2
        )
      );
    }
  }
}

if (esMain(import.meta)) {
  await copyEnvironmentRunFiles();
}
