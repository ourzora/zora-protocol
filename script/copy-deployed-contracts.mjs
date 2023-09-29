import { writeFile, readFile } from "fs/promises";
import esMain from "es-main";
import { glob } from "glob";

async function copyEnvironmentRunFiles(scriptName) {
  const latestFiles = await glob(
    `broadcast/${scriptName}/*/run-latest.json`
  );

  for (const file of latestFiles) {
    const latestDeploy = JSON.parse(await readFile(file));
    const { timestamp, commit, returns, chain } = latestDeploy;
    console.log({ timestamp, commit, returns, chain });
    const filePath = `addresses/${chain}.json`;
    const lastTimestamp = null;

    try {
      JSON.parse(await readFile(filePath)).timestamp || null;
    } catch {}

    if (!lastTimestamp || lastTimestamp < timestamp) {
      await writeFile(
        filePath,
        JSON.stringify(
          {
            ...JSON.parse(returns["0"].value),
            timestamp,
            commit,
          },
          null,
          2
        )
      );
    } else {
      console.log("old run-latest file, skipping");
    }
  }
}

if (esMain(import.meta)) {
  const command = process.argv[2];
  let scriptName = 'DeployAllToNewChain.s.sol';
    
  if (command === "upgrade"){
    scriptName = 'Upgrade.s.sol';
  } else if (command === 'deploy-premint') {
    scriptName = 'DeployNewPreminterAndFactoryProxy.s.sol'
  }

  await copyEnvironmentRunFiles(scriptName);
}
