import { writeFile, readFile } from "fs/promises";
import esMain from "es-main";
import { glob } from "glob";

type Deploy = {
  timestamp: number;
  commit: string;
  returns: { value: string }[];
  chain: number;
};
async function copyEnvironmentRunFiles() {
  const latestFiles = await glob(`broadcast/**/*run-latest.json`);

  const allFileContents = await Promise.all(
    latestFiles.map(async (file) => {
      const fileParts = file.split("/");
      const chainId = fileParts[fileParts.length - 2];
      return {
        chainId,
        contents: JSON.parse(await readFile(file, "utf-8")) as Deploy,
      };
    })
  );

  const groupedByChainId = allFileContents.reduce((acc, file) => {
    const chainId = file.chainId!;
    if (isNaN(Number(chainId))) return acc;

    if (!acc[chainId]) {
      acc[chainId] = [];
    }
    acc[chainId]!.push(file.contents);
    return acc;
  }, {} as Record<string, Deploy[]>);

  const withLatest = Object.entries(groupedByChainId).map(
    ([chainId, files]) => {
      const latest = files.sort((a, b) => b.timestamp! - a.timestamp!)[0];
      return {
        chainId,
        latest,
      };
    }
  );

  withLatest.forEach(async ({ chainId, latest }) => {
    const filePath = `addresses/${chainId}.json`;

    await writeFile(
      filePath,
      JSON.stringify(
        {
          ...JSON.parse(latest!.returns["0"]!.value),
          timestamp: latest!.timestamp,
          commit: latest!.commit,
        },
        null,
        2
      )
    );
  });
}

if (esMain(import.meta)) {
  await copyEnvironmentRunFiles();
}
