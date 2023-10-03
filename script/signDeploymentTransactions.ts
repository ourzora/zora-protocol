import { createAccount } from "@turnkey/viem";
import { TurnkeyClient } from "@turnkey/http";
import { Address, encodeFunctionData, parseAbi, LocalAccount, Hex } from "viem";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import { glob } from "glob";
import * as path from "path";
import * as dotenv from "dotenv";
import { writeFile, readFile } from "fs/promises";
import {
  ConfiguredSalt,
  DeterministicDeploymentConfig,
  GenericDeploymentConfiguration,
  signDeployFactory,
  signGenericDeploy,
} from "../package/deployment";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables from `.env.local`
dotenv.config({ path: path.resolve(__dirname, "../.env") });

type ChainConfig = {
  chainId: number;
  implementationAddress: Address;
  owner: Address;
};

async function signAndSaveSignatures({
  turnkeyAccount,
  chainConfigs,
  proxyName,
}: {
  turnkeyAccount: LocalAccount;
  chainConfigs: ChainConfig[];
  proxyName: "factoryProxy" | "premintExecutorProxy";
}) {
  const configFolder = path.resolve(
    __dirname,
    `../deterministicConfig/${proxyName}/`
  );
  const configFile = path.join(configFolder, "params.json");
  const deterministicDeployConfig = JSON.parse(
    await readFile(configFile, "utf-8")
  );

  const deploymentConfig: DeterministicDeploymentConfig = {
    proxyDeployerAddress:
      deterministicDeployConfig.proxyDeployerAddress as Address,
    proxySalt: deterministicDeployConfig.proxySalt as ConfiguredSalt,
    proxyShimSalt: deterministicDeployConfig.proxyShimSalt as ConfiguredSalt,
    proxyCreationCode: deterministicDeployConfig.proxyCreationCode as Address,
  };

  const signedConfigs = await Promise.all(
    chainConfigs.map(async (chainConfig) => {
      return {
        chainId: chainConfig.chainId,
        signature: await signDeployFactory({
          account: turnkeyAccount,
          implementationAddress: chainConfig.implementationAddress,
          owner: chainConfig.owner,
          chainId: chainConfig.chainId,
          deterministicDeploymentConfig: deploymentConfig,
        }),
      };
    })
  );

  // aggregate above to object of key value pair indexed by chain id as number:
  const byChainId = signedConfigs.reduce((acc, { chainId, signature }) => {
    acc[chainId] = signature;
    return acc;
  }, {} as { [key: number]: string });

  // write as json to ../deterministicConfig/factoryDeploySignatures.json:
  await writeFile(
    path.join(configFolder, "signatures.json"),
    JSON.stringify(byChainId, null, 2)
  );
}

async function signAndSaveGenericSignatures({
  turnkeyAccount,
  chainConfigs,
  proxyName,
}: {
  turnkeyAccount: LocalAccount;
  chainConfigs: ChainConfig[];
  proxyName: "upgradeGate";
}) {
  const configFolder = path.resolve(
    __dirname,
    `../deterministicConfig/${proxyName}/`
  );
  const configFile = path.join(configFolder, "params.json");
  const deterministicDeployConfig = JSON.parse(
    await readFile(configFile, "utf-8")
  );

  const deploymentConfig: GenericDeploymentConfiguration = {
    creationCode: deterministicDeployConfig.creationCode! as Hex,
    salt: deterministicDeployConfig.salt! as Hex,
    deployerAddress: deterministicDeployConfig.deployerAddress! as Address,
    upgradeGateAddress:
      deterministicDeployConfig.upgradeGateAddress! as Address,
    proxyDeployerAddress:
      deterministicDeployConfig.proxyDeployerAddress! as Address,
  };

  const upgradeGateAbi = parseAbi([
    //  ^? const abi: readonly [{ name: "balanceOf"; type: "function"; stateMutability:...
    "function initialize(address owner)",
  ]);

  const signedConfigs = await Promise.all(
    chainConfigs.map(async (chainConfig) => {
      const initCall = encodeFunctionData({
        abi: upgradeGateAbi,
        functionName: "initialize",
        args: [chainConfig.owner],
      });

      return {
        chainId: chainConfig.chainId,
        signature: await signGenericDeploy({
          account: turnkeyAccount,
          chainId: chainConfig.chainId,
          config: deploymentConfig,
          initCall,
        }),
      };
    })
  );

  // aggregate above to object of key value pair indexed by chain id as number:
  const byChainId = signedConfigs.reduce((acc, { chainId, signature }) => {
    acc[chainId] = signature;
    return acc;
  }, {} as { [key: number]: string });

  // write as json to ../deterministicConfig/factoryDeploySignatures.json:
  await writeFile(
    path.join(configFolder, "signatures.json"),
    JSON.stringify(byChainId, null, 2)
  );
}

const getFactoryImplConfigs = async () => {
  const addresseFiles = await glob(
    path.resolve(__dirname, "../addresses/*.json")
  );

  const chainConfigs = await Promise.all(
    addresseFiles.map(async (addressConfigFile) => {
      const chainId = parseInt(path.basename(addressConfigFile).split(".")[0]!);

      // read file and process JSON contents:
      const fileContents = await import(addressConfigFile);

      // read chain config file as json, which is located at: ../chainConfigs/${chainId}.json:
      const chainConfig = await import(
        path.resolve(__dirname, `../chainConfigs/${chainId}.json`)
      );

      return {
        chainId,
        implementationAddress: fileContents["FACTORY_IMPL"] as Address,
        owner: chainConfig["FACTORY_OWNER"] as Address,
      };
    })
  );

  return chainConfigs;
};

const getPreminterImplConfigs = async () => {
  const addresseFiles = await glob(
    path.resolve(__dirname, "../addresses/*.json")
  );

  const chainConfigs = await Promise.all(
    addresseFiles.map(async (addressConfigFile) => {
      const chainId = parseInt(path.basename(addressConfigFile).split(".")[0]!);

      // read file and process JSON contents:
      const fileContents = await import(addressConfigFile);

      // read chain config file as json, which is located at: ../chainConfigs/${chainId}.json:
      const chainConfig = await import(
        path.resolve(__dirname, `../chainConfigs/${chainId}.json`)
      );

      return {
        chainId,
        implementationAddress: fileContents["PREMINTER_IMPL"] as Address,
        owner: chainConfig["FACTORY_OWNER"] as Address,
      };
    })
  );

  return chainConfigs.filter((x) => x.implementationAddress !== undefined);
};

async function main() {
  // Create a Turnkey HTTP client with API key credentials
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    // This uses API key credentials.
    // If you're using passkeys, use `@turnkey/webauthn-stamper` to collect webauthn signatures:
    new ApiKeyStamper({
      apiPublicKey: process.env.TURNKEY_API_PUBLIC_KEY!,
      apiPrivateKey: process.env.TURNKEY_API_PRIVATE_KEY!,
    })
  );

  // Create the Viem custom account
  const turnkeyAccount = await createAccount({
    client: httpClient,
    organizationId: process.env.TURNKEY_ORGANIZATION_ID!,
    privateKeyId: process.env.TURNKEY_PRIVATE_KEY_ID!,
    // optional; will be fetched from Turnkey if not provided
    ethereumAddress: process.env.TURNKEY_TARGET_ADDRESS!,
  });

  await signAndSaveSignatures({
    turnkeyAccount,
    chainConfigs: await getFactoryImplConfigs(),
    proxyName: "factoryProxy",
  });

  await signAndSaveSignatures({
    turnkeyAccount,
    chainConfigs: await getPreminterImplConfigs(),
    proxyName: "premintExecutorProxy",
  });

  await signAndSaveGenericSignatures({
    turnkeyAccount,
    chainConfigs: await getFactoryImplConfigs(),
    proxyName: "upgradeGate",
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
