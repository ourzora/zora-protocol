import { writeFile, readFile } from "fs/promises";
import esMain from "es-main";
// @ts-ignore
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
    latestFiles.map(async (file: string) => {
      const fileParts = file.split("/");
      const chainId = fileParts[fileParts.length - 2];
      const parsed = JSON.parse(await readFile(file, "utf-8")) as Deploy;
      const returns = parsed.returns[0]?.value || "{}";

      // a recent version of forge added a bug where the returns value with some sort of url based encoding.
      // the below code is a hack to fix this. It should be removed once forge is fixed.
      // use string regex replace all to remove all instances of \\ from returns (this appeared in a wierd version of forge)
      // also opening and closing quotes that incorrecly appear before opening bracket:
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
    }),
  );

  const groupedByChainId = allFileContents.reduce(
    (acc: any, file: any) => {
      const chainId = file.chainId!;
      if (isNaN(Number(chainId))) return acc;

      if (!acc[chainId]) {
        acc[chainId] = [];
      }
      acc[chainId]!.push(file);
      return acc;
    },
    {} as Record<string, Deploy[]>,
  );

  const withLatest = Object.entries(groupedByChainId).map(
    ([chainId, files]: any) => {
      const latest = files.sort(
        (a: any, b: any) => b.timestamp! - a.timestamp!,
      )[0];
      return {
        chainId,
        latest,
      };
    },
  );

  withLatest.forEach(async ({ chainId, latest }) => {
    const filePath = `addresses/${chainId}.json`;

    await writeFile(
      filePath,
      JSON.stringify(
        {
          ...latest!.returns,
          timestamp: latest!.timestamp,
          commit: latest!.commit,
        },
        null,
        2,
      ),
    );
  });
}

if (esMain(import.meta)) {
  await copyEnvironmentRunFiles();
}
