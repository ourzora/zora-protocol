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
} from "viem";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import * as path from "path";
import * as dotenv from "dotenv";
import { readFile } from "fs/promises";
import { zoraMintsManagerImplABI } from "@zoralabs/mints-contracts";
import { abi as proxyDeployerAbi } from "../out/DeterministicUUPSProxyDeployer.sol/DeterministicUUPSProxyDeployer.json";

import { fileURLToPath } from "url";
import { dirname } from "path";
import { arbitrumSepolia, sepolia, zora, zoraSepolia } from "viem/chains";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables from `.env.local`
dotenv.config({ path: path.resolve(__dirname, "../.env") });

function getChainIdPositionalArg() {
  // parse chain id as first argument:
  const chainIdArg = process.argv[2];

  if (!chainIdArg) {
    throw new Error("Must provide chain id as first argument");
  }

  return parseInt(chainIdArg);
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

type DeterminsticContractConfig = {
  salt: Hex;
  creationCode: Hex;
  deployedAddress: Hex;
  constructorArgs: Hex;
  contractName: string;
};

type MintsDeterminsticConfig = {
  manager: DeterminsticContractConfig;
  mints1155: DeterminsticContractConfig;
};

type InitializationConfig = {
  proxyAdmin: Address;
  initialImplementationAddress: Address;
  initialImplementationCall: Hex;
};

const loadProxyDeployerAddress = async () => {
  const proxyDeployerConfig = JSON.parse(
    await readFile(
      path.resolve(
        __dirname,
        "../deterministicConfig/proxyDeployer/params.json",
      ),
      "utf-8",
    ),
  );

  return proxyDeployerConfig.deployedAddress as Address;
};

const loadDeterministicTransparentProxyConfig = async (
  proxyName: string,
): Promise<MintsDeterminsticConfig> => {
  const filePath = path.resolve(
    __dirname,
    `../deterministicConfig/${proxyName}/params.json`,
  );

  // read file as json, casting it as return value:
  const fileContents = JSON.parse(await readFile(filePath, "utf-8"));

  return fileContents as MintsDeterminsticConfig;
};

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
];

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
    `../chainConfigs/${chainId}.json`,
  );
  const addressesPath = path.resolve(__dirname, `../addresses/${chainId}.json`);

  const chainConfig = JSON.parse(await readFile(chainConfigPath, "utf-8")) as {
    PROXY_ADMIN: Address;
    MINTS_OWNER: Address;
  };

  await validateIsValidSafe(chainConfig.PROXY_ADMIN, publicClient);
  await validateIsValidSafe(chainConfig.MINTS_OWNER, publicClient);

  const addresses = JSON.parse(await readFile(addressesPath, "utf-8")) as {
    MINTS_MANAGER_IMPL: Address;
  };

  const initialEthTokenId = 1n;
  const initialEthTokenPrice = parseEther("0.000777");

  const metadataBaseURI = "https://zora.co/assets/mints/metadata/";
  const contractURI = "https://zora.co/assets/mints/metadata/";

  // this will initialize the mints contract with the owner, the initial token id, and the initial token price:
  // and will be called when the proxy will be initially upgraded to the implementation:
  const initialImplementationCall = encodeFunctionData({
    abi: zoraMintsManagerImplABI,
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
    initialImplementationAddress: addresses.MINTS_MANAGER_IMPL,
    initialImplementationCall,
  };
};

function getChain(chainId: any) {
  if (chainId === zoraSepolia.id) return zoraSepolia;
  if (chainId === sepolia.id) return sepolia;
  if (chainId === arbitrumSepolia.id) return arbitrumSepolia;
  if (chainId === zora.id) return zora;

  throw new Error(`Chain id ${chainId} not supported`);
}

const makeClientsFromAccount = async ({
  chainId,
  account,
}: {
  chainId: Number;
  account: LocalAccount;
}): Promise<{
  publicClient: PublicClient;
  walletClient: WalletClient;
}> => {
  const chain = getChain(chainId);

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

async function deployMintsManagerProxy({
  publicClient,
  walletClient,
  account,
  determinsticTransparentProxyConfig,
  initializationConfig,
  proxyDeployerAddress,
}: {
  determinsticTransparentProxyConfig: MintsDeterminsticConfig;
  initializationConfig: InitializationConfig;
  proxyDeployerAddress: `0x${string}`;
  publicClient: PublicClient;
  walletClient: WalletClient;
  account: Account;
}) {
  // simulate transaction
  const { request } = await publicClient.simulateContract({
    abi: proxyDeployerAbi,
    address: proxyDeployerAddress,
    functionName: "safeCreate2AndUpgradeToAndCall",
    args: [
      determinsticTransparentProxyConfig.manager.salt,
      determinsticTransparentProxyConfig.manager.creationCode,
      initializationConfig.initialImplementationAddress,
      initializationConfig.initialImplementationCall,
      determinsticTransparentProxyConfig.manager.deployedAddress,
    ],
    account,
  });

  await walletClient.writeContract(request);
}

function printVerificationCommand({
  deployedAddress,
  constructorArgs,
  contractName,
}: DeterminsticContractConfig) {
  console.log("verify the contract with the following command:");

  console.log(
    `forge verify-contract  ${deployedAddress} ${contractName} $(chains (chainName) --verify) --constructor-args ${constructorArgs}`,
  );
}

/// Deploy the mints manager and 1155 contract deteriministically using turnkey
async function main() {
  // Create a Turnkey HTTP client with API key credentials
  const turnkeyAccount = await loadTurnkeyAccount();

  // get the chain id from the first positional argument
  const chainId = getChainIdPositionalArg();

  // load the determinstic proxy config for the mints manager and 1155 contract
  const mintsProxyConfig =
    await loadDeterministicTransparentProxyConfig("mintsProxy");

  const { publicClient, walletClient } = await makeClientsFromAccount({
    chainId,
    account: turnkeyAccount,
  });

  // generate the initialization call config for the mints manager, including
  // the initial implementation address, and the initial implementation call
  const initializationConfig = await generateInitializationConfig({
    chainId,
    publicClient,
    mints1155Config: mintsProxyConfig.mints1155,
  });

  // get the deterministic proxy deployer address, which will be used to create the contracts
  // at determinstic addresses
  const proxyDeployerAddress = await loadProxyDeployerAddress();

  // call the proxy deployer to deploy the contracts, using the known salts, creation codes, and constructor args
  await deployMintsManagerProxy({
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

  printVerificationCommand(mintsProxyConfig.manager);
  printVerificationCommand(mintsProxyConfig.mints1155);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
