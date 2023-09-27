import { createAccount } from "@turnkey/viem";
import { TurnkeyClient } from "@turnkey/http";
import { Address } from "viem";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
// import { getDeployFactoryProxyDeterminsticTx } from '../package/deployment';
// import { testConfig } from "../package/deploymentConfig";
import deployConfig from '../determinsticConfig/deployConfig.json';
import { glob } from "glob";
import * as path from "path";
import * as dotenv from "dotenv";
import { promisify } from 'util';
import { writeFile } from 'fs';
import { ConfiguredSalt, DeterminsticDeploymentConfig, signDeployFactory } from "../package/deployment";
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const writeFileAsync = promisify(writeFile);

// Load environment variables from `.env.local`
dotenv.config({ path: path.resolve(__dirname, "../.env") });

async function main() {
  // Create a Turnkey HTTP client with API key credentials
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    // This uses API key credentials.
    // If you're using passkeys, use `@turnkey/webauthn-stamper` to collect webauthn signatures:
    // new WebauthnStamper({...options...})
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

  const addresseFiles = await glob(
    path.resolve(__dirname, "../addresses/*.json")
  );

  console.log(path.resolve(__dirname, "../addresses/*.json"));

  const chainConfigs = await Promise.all(addresseFiles.map(async addressConfigFile => {
    const chainId = parseInt(path.basename(addressConfigFile).split(".")[0]);

    // read file and process JSON contents: 
    const fileContents = await import(addressConfigFile);

    // read chain config file as json, which is located at: ../chainConfigs/${chainId}.json:
    const chainConfig = await import(path.resolve(__dirname, `../chainConfigs/${chainId}.json`));

    return {
      chainId,
      factoryImpl: fileContents['FACTORY_IMPL'] as Address,
      owner: chainConfig['FACTORY_OWNER'] as Address
    }
  }));

  const deploymentConfig: DeterminsticDeploymentConfig = {
    factoryDeployerAddress: deployConfig.determinsticDeployerAddress as Address,
    factoryProxySalt: deployConfig.factoryProxySalt as ConfiguredSalt,
    proxyShimSalt: deployConfig.proxyShimSalt as ConfiguredSalt
  }

  const signedConfigs = await Promise.all(chainConfigs.map(async chainConfig => {
    return {
      chainId: chainConfig.chainId,
      signedConfig: {
        signature: await signDeployFactory({
          account: turnkeyAccount,
          factoryImplAddress: chainConfig.factoryImpl,
          factoryOwner: chainConfig.owner,
          chainId: chainConfig.chainId,
          determinsticDeploymentConfig: deploymentConfig
        }),
        ...deploymentConfig
      }
    }
  }));


  // aggregate above to object of key value pair indexed by chain id as number:
  const byChainId = signedConfigs.reduce((acc, { chainId, signedConfig }) => {
    acc[chainId] = signedConfig;
    return acc;
  }, {} as { [key: number]: typeof signedConfigs[0]['signedConfig'] } );

  // write as json to ../determinsticConfig/factoryDeploySignatures.json:
  await writeFileAsync(path.resolve(__dirname, "../determinsticConfig/factoryDeploySignatures.json"), JSON.stringify(byChainId, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});