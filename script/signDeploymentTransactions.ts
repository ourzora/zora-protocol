import { createAccount } from "@turnkey/viem";
import { TurnkeyClient } from "@turnkey/http";
import { Address, LocalAccount } from "viem";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import factoryProxyDeployConfig from '../determinsticConfig/factoryProxy/params.json';
import { glob } from "glob";
import * as path from "path";
import * as dotenv from "dotenv";
import { promisify } from 'util';
import { writeFile, readFile } from 'fs';
import { ConfiguredSalt, DeterminsticDeploymentConfig, signDeployFactory } from "../package/deployment";
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { config } from "process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const writeFileAsync = promisify(writeFile);
const readFileAsync = promisify(readFile);

// Load environment variables from `.env.local`
dotenv.config({ path: path.resolve(__dirname, "../.env") });

type ChainConfig = {
  chainId: number,
  implementationAddress: Address,
  owner: Address
};

async function signAndSaveSignatures({
  turnkeyAccount,
  chainConfigs,
  proxyName
}: {
  turnkeyAccount: LocalAccount,
  chainConfigs: ChainConfig[],
  proxyName: "factoryProxy" | "premintExecutorProxy"
}) {
  const configFolder = path.resolve(__dirname, `../determinsticConfig/${proxyName}/`);
  const configFile = path.join(configFolder, 'params.json');
  const determinsticDeployConfig = JSON.parse(await readFileAsync(configFile, 'utf-8'));

  const deploymentConfig: DeterminsticDeploymentConfig = {
    proxyDeployerAddress: determinsticDeployConfig.proxyDeployerAddress as Address,
    proxySalt: determinsticDeployConfig.proxySalt as ConfiguredSalt,
    proxyShimSalt: determinsticDeployConfig.proxyShimSalt as ConfiguredSalt,
    proxyCreationCode: determinsticDeployConfig.proxyCreationCode as Address
  }

  const signedConfigs = await Promise.all(chainConfigs.map(async chainConfig => {
    return {
      chainId: chainConfig.chainId,
        signature: await signDeployFactory({
          account: turnkeyAccount,
          implementationAddress: chainConfig.implementationAddress,
          owner: chainConfig.owner,
          chainId: chainConfig.chainId,
          determinsticDeploymentConfig: deploymentConfig
        }),
    }
  }));

  // aggregate above to object of key value pair indexed by chain id as number:
  const byChainId = signedConfigs.reduce((acc, { chainId, signature }) => {
    acc[chainId] = signature;
    return acc;
  }, {} as { [key: number]: string } );

  // write as json to ../determinsticConfig/factoryDeploySignatures.json:
  await writeFileAsync(path.join(configFolder, "signatures.json"), JSON.stringify(byChainId, null, 2));
}

const getFactoryImplConfigs = async () => {
  const addresseFiles = await glob(
    path.resolve(__dirname, "../addresses/*.json")
  );

  const chainConfigs = await Promise.all(addresseFiles.map(async addressConfigFile => {
    const chainId = parseInt(path.basename(addressConfigFile).split(".")[0]);

    // read file and process JSON contents: 
    const fileContents = await import(addressConfigFile);

    // read chain config file as json, which is located at: ../chainConfigs/${chainId}.json:
    const chainConfig = await import(path.resolve(__dirname, `../chainConfigs/${chainId}.json`));

    return {
      chainId,
      implementationAddress: fileContents['FACTORY_IMPL'] as Address,
      owner: chainConfig['FACTORY_OWNER'] as Address
    }
  }));

  return chainConfigs;
}

const getPreminterImplConfigs = async () => {
  const addresseFiles = await glob(
    path.resolve(__dirname, "../addresses/*.json")
  );

  const chainConfigs = await Promise.all(addresseFiles.map(async addressConfigFile => {
    const chainId = parseInt(path.basename(addressConfigFile).split(".")[0]);

    // read file and process JSON contents: 
    const fileContents = await import(addressConfigFile);

    // read chain config file as json, which is located at: ../chainConfigs/${chainId}.json:
    const chainConfig = await import(path.resolve(__dirname, `../chainConfigs/${chainId}.json`));

    return {
      chainId,
      implementationAddress: fileContents['PREMINTER_IMPL'] as Address,
      owner: chainConfig['FACTORY_OWNER'] as Address
    }
  }));



  return chainConfigs.filter(x => x.implementationAddress !== undefined);
}

async function main() {
  // Create a Turnkey HTTP client with API key credentials
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    // This uses API key credentials.
    // If you're using passkeys, use `@turnkey/webauthn-stamper` to collect webauthn signatures:
    new ApiKeyStamper({
      apiPublicKey: process.env.API_PUBLIC_KEY!,
      apiPrivateKey: process.env.API_PRIVATE_KEY!,
    })
  );

  // Create the Viem custom account
  const turnkeyAccount = await createAccount({
    client: httpClient,
    organizationId: "f7e5bec5-b7f9-486a-a8c3-cd1ec7362709",
    privateKeyId: "3e3c5029-7ad7-4559-936f-93d21763143b",
    // optional; will be fetched from Turnkey if not provided
    ethereumAddress: "0x4F9991C82C76aE04CC39f23aB909AA919886ba12"
  });

  await signAndSaveSignatures({
    turnkeyAccount,
    chainConfigs: await getFactoryImplConfigs(),
    proxyName: "factoryProxy"
  });

  await signAndSaveSignatures({
    turnkeyAccount,
    chainConfigs: await getPreminterImplConfigs(),
    proxyName: "premintExecutorProxy"
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});