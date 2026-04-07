import { createAccount } from "@turnkey/viem";
import { TurnkeyClient } from "@turnkey/http";
import {
  Address,
  encodeFunctionData,
  LocalAccount,
  Hex,
  parseEther,
  createWalletClient,
  http,
  createPublicClient,
  PublicClient,
  Account,
  WalletClient,
  Chain,
} from "viem";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import * as path from "path";
import * as dotenv from "dotenv";
import { readFile } from "fs/promises";
import { zoraSparksManagerImplABI } from "../package";
import { abi as proxyDeployerAbi } from "../out/DeterministicUUPSProxyDeployer.sol/DeterministicUUPSProxyDeployer.json";
import * as chains from "viem/chains";

import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables from `.env.local`
dotenv.config({ path: path.resolve(__dirname, "../.env") });

function getChainIdPositionalArg() {
  // parse chain id as first argument:
  const chainId = process.argv[2];

  if (!chainId) {
    throw new Error("Must provide chain ID as first argument");
  }

  return chainId;
}

function getChain(chainId: string): Chain {
  const allChains = Object.values(chains);

  const result = allChains.find((chain) => chain.id.toString() === chainId);

  if (!result) {
    throw new Error(`Chain ${chainId} not found`);
  }

  return result;
}

const loadTurnkeyAccount = async () => {
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    // This uses API key credentials.
    // If you're using passkeys, use `@turnkey/webauthn-stamper` to collect webauthn signatures:
    new ApiKeyStamper({
      apiPublicKey: process.env.TURNKEY_API_PUBLIC_KEY!,
      apiPrivateKey: process.env.TURNKEY_API_PRIVATE_KEY!,
    }),
  );

  // Create the Viem custom account
  return await createAccount({
    client: httpClient,
    organizationId: process.env.TURNKEY_ORGANIZATION_ID!,
    signWith: process.env.TURNKEY_PRIVATE_KEY_ID!,
    // optional; will be fetched from Turnkey if not provided
    ethereumAddress: process.env.TURNKEY_TARGET_ADDRESS!,
  });
};

type DeterministicContractConfig = {
  salt: Hex;
  creationCode: Hex;
  deployedAddress: Hex;
  constructorArgs: Hex;
  contractName: string;
};

type SparksDeterministicConfig = {
  manager: DeterministicContractConfig;
  sparks1155: DeterministicContractConfig;
};

type InitializationConfig = {
  proxyAdmin: Address;
  initialImplementationAddress: Address;
  initialImplementationCall: Hex;
};

const loadProxyDeployerAddress = async () => {
  const proxyDeployerConfig = JSON.parse(
    await readFile(
      path.resolve(__dirname, "../deterministicConfig/uupsProxyDeployer.json"),
      "utf-8",
    ),
  );

  return proxyDeployerConfig.deployedAddress as Address;
};

const loadDeterministicTransparentProxyConfig = async (
  proxyName: string,
): Promise<SparksDeterminsticConfig> => {
  const filePath = path.resolve(
    __dirname,
    `../deterministicConfig/${proxyName}.json`,
  );

  // read file as json, casting it as return value:
  const fileContents = JSON.parse(await readFile(filePath, "utf-8"));

  return fileContents as SparksDeterminsticConfig;
};

const validateIsValidSafe = async (
  address: Address,
  publicClient: PublicClient,
) => {
  const safeAbi = [
    {
      constant: true,
      inputs: [],
      name: "getOwners",
      outputs: [
        {
          name: "",
          type: "address[]",
        },
      ],
      payable: false,
      stateMutability: "view",
      type: "function",
    },
  ] as const;

  const owners = await publicClient.readContract({
    abi: safeAbi,
    functionName: "getOwners",
    address,
  });

  if (owners.length === 0) {
    throw new Error(`Invalid safe at address ${address}, no owners`);
  }
};

const generateInitializationConfig = async ({
  chainId,
  publicClient,
  mints1155Config,
}: {
  chainId: number;
  publicClient: PublicClient;
  mints1155Config: DeterminsticContractConfig;
}): Promise<InitializationConfig> => {
  const chainConfigPath = path.resolve(
    __dirname,
    `../../shared-contracts/chainConfigs/${chainId}.json`,
  );
  const addressesPath = path.resolve(__dirname, `../addresses/${chainId}.json`);

  const chainConfig = JSON.parse(await readFile(chainConfigPath, "utf-8")) as {
    PROXY_ADMIN: Address;
  };

  await validateIsValidSafe(chainConfig.PROXY_ADMIN, publicClient);

  const addresses = JSON.parse(await readFile(addressesPath, "utf-8")) as {
    SPARKS_MANAGER_IMPL: Address;
  };

  const initialEthTokenId = 1n;
  const initialEthTokenPrice = parseEther("0.000001");

  const metadataBaseURI = "https://zora.co/assets/sparks/metadata/";
  const contractURI = "https://zora.co/assets/sparks/metadata/";

  // this will initialize the mints contract with the owner, the initial token id, and the initial token price:
  // and will be called when the proxy will be initially upgraded to the implementation:
  const initialImplementationCall = encodeFunctionData({
    abi: zoraSparksManagerImplABI,
    functionName: "initialize",
    args: [
      chainConfig.PROXY_ADMIN,
      mints1155Config.salt,
      mints1155Config.creationCode,
      initialEthTokenId,
      initialEthTokenPrice,
      metadataBaseURI,
      contractURI,
    ],
  });

  return {
    proxyAdmin: chainConfig.PROXY_ADMIN,
    initialImplementationAddress: addresses.SPARKS_MANAGER_IMPL,
    initialImplementationCall,
  };
};

const makeClientsFromAccount = async ({
  chain,
  account,
}: {
  chain: Chain;
  account: LocalAccount;
}): Promise<{
  publicClient: PublicClient;
  walletClient: WalletClient;
}> => {
  const walletClient = createWalletClient({
    account,
    chain,
    transport: http(),
  });

  const publicClient = createPublicClient({
    chain,
    transport: http(),
  }) as PublicClient;

  return {
    walletClient,
    publicClient,
  };
};

async function deploySparksManagerProxy({
  publicClient,
  walletClient,
  account,
  deterministicTransparentProxyConfig,
  initializationConfig,
  proxyDeployerAddress,
}: {
  deterministicTransparentProxyConfig: SparksDeterministicConfig;
  initializationConfig: InitializationConfig;
  proxyDeployerAddress: `0x${string}`;
  publicClient: PublicClient;
  walletClient: WalletClient;
  account: Account;
}) {
  // const call = encodeFunctionData({
  //   abi: proxyDeployerAbi,
  //   functionName: "safeCreate2AndUpgradeToAndCall",
  //   args: [
  //     deterministicTransparentProxyConfig.manager.salt,
  //     deterministicTransparentProxyConfig.manager.creationCode,
  //     initializationConfig.initialImplementationAddress,
  //     initializationConfig.initialImplementationCall,
  //     deterministicTransparentProxyConfig.manager.deployedAddress,
  //   ],
  // });

  // simulate transaction
  const { request } = await publicClient.simulateContract({
    abi: proxyDeployerAbi,
    address: proxyDeployerAddress,
    functionName: "safeCreate2AndUpgradeToAndCall",
    args: [
      deterministicTransparentProxyConfig.manager.salt,
      deterministicTransparentProxyConfig.manager.creationCode,
      initializationConfig.initialImplementationAddress,
      initializationConfig.initialImplementationCall,
      deterministicTransparentProxyConfig.manager.deployedAddress,
    ],
    account,
  });

  await walletClient.writeContract(request);
}

function printVerificationCommand({
  deployedAddress,
  constructorArgs,
  contractName,
  chainId,
}: DeterminsticContractConfig & { chainId: string }) {
  console.log("verify the contract with the following command:");

  console.log(
    `forge verify-contract ${deployedAddress} ${contractName} $(chains ${chainId} --verify) --constructor-args ${constructorArgs} --watch`,
  );
}

/// Deploy the mints manager and 1155 contract deteriministically using turnkey
async function main() {
  // Create a Turnkey HTTP client with API key credentials
  const turnkeyAccount = await loadTurnkeyAccount();

  // get the chain id from the first positional argument
  const chainId = getChainIdPositionalArg();

  // load the deterministic proxy config for the mints manager and 1155 contract
  const mintsProxyConfig =
    await loadDeterministicTransparentProxyConfig("sparksProxy");

  const chain = (await getChain(chainId)) as Chain;

  const { publicClient, walletClient } = await makeClientsFromAccount({
    chain,
    account: turnkeyAccount,
  });

  // generate the initialization call config for the mints manager, including
  // the initial implementation address, and the initial implementation call
  const initializationConfig = await generateInitializationConfig({
    chainId: chain.id,
    publicClient,
    mints1155Config: mintsProxyConfig.sparks1155,
  });

  // get the deterministic proxy deployer address, which will be used to create the contracts
  // at deterministic addresses
  const proxyDeployerAddress = await loadProxyDeployerAddress();

  // call the proxy deployer to deploy the contracts, using the known salts, creation codes, and constructor args
  await deploySparksManagerProxy({
    determinsticTransparentProxyConfig: mintsProxyConfig,
    initializationConfig,
    proxyDeployerAddress,
    publicClient,
    account: turnkeyAccount,
    walletClient,
  });

  console.log(
    `${mintsProxyConfig.manager.contractName} contract deployed to ${mintsProxyConfig.manager.deployedAddress}`,
  );

  printVerificationCommand({
    ...mintsProxyConfig.manager,
    chainId,
  });
  printVerificationCommand({
    ...mintsProxyConfig.sparks1155,
    chainId,
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
