import { readFile, writeFile } from "fs/promises";
import { glob } from "glob";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { Address } from "viem";
import {} from "@uniswap/v3-periphery";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function fileExistsAtDest(targetFile: string) {
  try {
    await readFile(targetFile, "utf-8");
    return true;
  } catch (e) {
    return false;
  }
}

export const copyConfig = async () => {
  const chainConfigsFiles = await glob(
    join(__dirname, "../../1155-deployments/chainConfigs/*.json"),
  );

  for (let i = 0; i < chainConfigsFiles.length; i++) {
    const chainConfigFile = chainConfigsFiles[i]!;
    const parts = chainConfigFile.split("/");

    const chainId = parseInt(parts[parts.length - 1]!.split(".")[0]!);

    const fileContents = JSON.parse(await readFile(chainConfigFile, "utf-8"));

    const owner = fileContents.FACTORY_OWNER as Address;
    const zoraRecipient = fileContents.MINT_FEE_RECIPIENT as Address;

    const targetFile = join(__dirname, `../chainConfigs/${chainId}.json`);

    if (await fileExistsAtDest(targetFile)) {
      const existingConfig: {
        PROXY_ADMIN?: Address;
        ZORA_RECIPIENT?: Address;
        NONFUNGIBLE_POSITION_MANAGER?: Address;
      } = JSON.parse(await readFile(targetFile, "utf-8"));

      const newConfig = {
        NONFUNGIBLE_POSITION_MANAGER: "0x",
        ...existingConfig,
        PROXY_ADMIN: owner,
        ZORA_RECIPIENT: zoraRecipient,
      };

      await writeFile(targetFile, JSON.stringify(newConfig, null, 2));
    }
  }
};

copyConfig();
