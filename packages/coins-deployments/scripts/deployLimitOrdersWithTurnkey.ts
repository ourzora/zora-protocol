import { createAccount } from "@turnkey/viem";
import { TurnkeyClient } from "@turnkey/http";
import { Address, Hex, createWalletClient, http, publicActions } from "viem";
import { base } from "viem/chains";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import * as path from "path";
import * as dotenv from "dotenv";
import { readFile } from "fs/promises";
import { fileURLToPath } from "url";
import { dirname } from "path";
import { execSync } from "child_process";
import { verifyContract } from "./lib/verify";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables from `.env`
dotenv.config({ path: path.resolve(__dirname, "../.env") });

type LimitOrderConfig = {
  salt: Hex;
  creationCode: Hex;
  constructorArgs: Hex;
  deployedAddress: Address;
  contractName: string;
};

const IMMUTABLE_CREATE2_FACTORY =
  "0x0000000000FFe8B47B3e2130213B802212439497" as Address;

// ImmutableCreate2Factory ABI for safeCreate2 function
const IMMUTABLE_CREATE2_FACTORY_ABI = [
  {
    inputs: [
      { name: "salt", type: "bytes32" },
      { name: "initializationCode", type: "bytes" },
    ],
    name: "safeCreate2",
    outputs: [{ name: "deploymentAddress", type: "address" }],
    stateMutability: "payable",
    type: "function",
  },
] as const;

function getChainIdPositionalArg(): number {
  const chainIdArg = process.argv[2];

  if (!chainIdArg) {
    throw new Error(
      "Must provide chain id as first argument (e.g., 8453 for Base)",
    );
  }

  return parseInt(chainIdArg);
}

function isDryRun(): boolean {
  return process.argv.includes("--dry-run");
}

function isVerifyOnly(): boolean {
  return process.argv.includes("--verify-only");
}

function getRpcUrl(chainName: string): string {
  try {
    const result = execSync(`chains ${chainName} --rpc`, {
      encoding: "utf-8",
    }).trim();

    // Parse "--rpc-url https://..." to get just the URL
    const match = result.match(/--rpc-url\s+(\S+)/);
    if (match) {
      return match[1];
    }

    // If no match, assume the result is already just the URL
    return result;
  } catch (error) {
    throw new Error(`Failed to get RPC URL for chain ${chainName}: ${error}`);
  }
}

async function readConfigs(): Promise<{
  limitOrderBookConfig: LimitOrderConfig;
  swapRouterConfig: LimitOrderConfig;
}> {
  const limitOrderBookConfigFile = path.resolve(
    __dirname,
    "../deterministicConfig/zoraLimitOrderBook.json",
  );
  const swapRouterConfigFile = path.resolve(
    __dirname,
    "../deterministicConfig/zoraRouter.json",
  );

  console.log(`Reading configs...`);
  const limitOrderBookConfig: LimitOrderConfig = JSON.parse(
    await readFile(limitOrderBookConfigFile, "utf-8"),
  );
  const swapRouterConfig: LimitOrderConfig = JSON.parse(
    await readFile(swapRouterConfigFile, "utf-8"),
  );

  return { limitOrderBookConfig, swapRouterConfig };
}

async function verifyContracts(
  limitOrderBookConfig: LimitOrderConfig,
  swapRouterConfig: LimitOrderConfig,
): Promise<void> {
  console.log("\n=== Verifying Contracts ===");

  try {
    await verifyContract(
      limitOrderBookConfig.deployedAddress,
      "ZoraLimitOrderBook",
      "base",
      limitOrderBookConfig.constructorArgs,
    );

    await verifyContract(
      swapRouterConfig.deployedAddress,
      "SwapWithLimitOrders",
      "base",
      swapRouterConfig.constructorArgs,
    );

    console.log("\n✅ Verification complete");
  } catch (error) {
    console.error("\n⚠️  Verification failed");
    console.error("You can verify manually later using:");
    console.error(
      `  forge verify-contract ${limitOrderBookConfig.deployedAddress} ZoraLimitOrderBook --constructor-args ${limitOrderBookConfig.constructorArgs} $(chains base --deploy)`,
    );
    console.error(
      `  forge verify-contract ${swapRouterConfig.deployedAddress} SwapWithLimitOrders --constructor-args ${swapRouterConfig.constructorArgs} $(chains base --deploy)`,
    );
    throw error;
  }
}

async function simulateDeployments(
  walletClient: any,
  turnkeyAccount: any,
  limitOrderBookConfig: LimitOrderConfig,
  swapRouterConfig: LimitOrderConfig,
): Promise<{ limitOrderBookRequest: any; swapRouterRequest: any }> {
  console.log("\n=== Simulating Deployments ===");

  const { request: limitOrderBookReq, result: limitOrderBookResult } =
    await walletClient.simulateContract({
      account: turnkeyAccount,
      address: IMMUTABLE_CREATE2_FACTORY,
      abi: IMMUTABLE_CREATE2_FACTORY_ABI,
      functionName: "safeCreate2",
      args: [limitOrderBookConfig.salt, limitOrderBookConfig.creationCode],
    });

  console.log("✅ ZoraLimitOrderBook simulation successful");
  console.log(`   Result: ${limitOrderBookResult}`);
  console.log(`   Expected: ${limitOrderBookConfig.deployedAddress}`);
  if (
    limitOrderBookResult.toLowerCase() !==
    limitOrderBookConfig.deployedAddress.toLowerCase()
  ) {
    throw new Error(
      `Address mismatch! Simulated: ${limitOrderBookResult}, Expected: ${limitOrderBookConfig.deployedAddress}`,
    );
  }

  const { request: swapRouterReq, result: swapRouterResult } =
    await walletClient.simulateContract({
      account: turnkeyAccount,
      address: IMMUTABLE_CREATE2_FACTORY,
      abi: IMMUTABLE_CREATE2_FACTORY_ABI,
      functionName: "safeCreate2",
      args: [swapRouterConfig.salt, swapRouterConfig.creationCode],
    });

  console.log("\n✅ SwapWithLimitOrders simulation successful");
  console.log(`   Result: ${swapRouterResult}`);
  console.log(`   Expected: ${swapRouterConfig.deployedAddress}`);
  if (
    swapRouterResult.toLowerCase() !==
    swapRouterConfig.deployedAddress.toLowerCase()
  ) {
    throw new Error(
      `Address mismatch! Simulated: ${swapRouterResult}, Expected: ${swapRouterConfig.deployedAddress}`,
    );
  }

  console.log("\n✅ All simulations passed!");

  return {
    limitOrderBookRequest: limitOrderBookReq,
    swapRouterRequest: swapRouterReq,
  };
}

async function deployContracts(
  walletClient: any,
  limitOrderBookRequest: any,
  swapRouterRequest: any,
  limitOrderBookConfig: LimitOrderConfig,
  swapRouterConfig: LimitOrderConfig,
): Promise<void> {
  // Deploy contracts sequentially with validation between steps
  // Note: This is NOT an atomic transaction. If the second deployment fails,
  // the first contract will remain deployed. This is acceptable since both
  // contracts are deterministic and can be independently deployed.

  console.log("\n=== Deploying ZoraLimitOrderBook ===");
  const limitOrderBookHash = await walletClient.writeContract(
    limitOrderBookRequest,
  );
  console.log(`Transaction hash: ${limitOrderBookHash}`);
  console.log("Waiting for confirmation...");
  const limitOrderBookReceipt = await walletClient.waitForTransactionReceipt({
    hash: limitOrderBookHash,
  });
  console.log(
    `✅ Deployed at block ${limitOrderBookReceipt.blockNumber}, Gas used: ${limitOrderBookReceipt.gasUsed}`,
  );

  // Verify first deployment succeeded before continuing
  if (limitOrderBookReceipt.status !== "success") {
    throw new Error(
      `ZoraLimitOrderBook deployment failed with status: ${limitOrderBookReceipt.status}`,
    );
  }

  console.log("\n=== Deploying SwapWithLimitOrders ===");
  const swapRouterHash = await walletClient.writeContract(swapRouterRequest);
  console.log(`Transaction hash: ${swapRouterHash}`);
  console.log("Waiting for confirmation...");
  const swapRouterReceipt = await walletClient.waitForTransactionReceipt({
    hash: swapRouterHash,
  });
  console.log(
    `✅ Deployed at block ${swapRouterReceipt.blockNumber}, Gas used: ${swapRouterReceipt.gasUsed}`,
  );

  // Verify second deployment succeeded
  if (swapRouterReceipt.status !== "success") {
    throw new Error(
      `SwapWithLimitOrders deployment failed with status: ${swapRouterReceipt.status}`,
    );
  }

  console.log("\n=== Deployment Complete ===");
  console.log(`✅ Both contracts deployed successfully`);
  console.log(`ZORA_LIMIT_ORDER_BOOK: ${limitOrderBookConfig.deployedAddress}`);
  console.log(`ZORA_ROUTER: ${swapRouterConfig.deployedAddress}`);
}

async function main() {
  console.log("=== Turnkey Limit Order Deployment ===\n");

  const chainId = getChainIdPositionalArg();
  console.log(`Chain ID: ${chainId}\n`);

  // Only support Base for now
  if (chainId !== 8453) {
    throw new Error("Only Base (chainId 8453) is currently supported");
  }

  // Read configurations
  const { limitOrderBookConfig, swapRouterConfig } = await readConfigs();

  // If verify-only mode, skip deployment and just verify
  if (isVerifyOnly()) {
    console.log("\n=== Verify Only Mode ===");
    console.log(`ZoraLimitOrderBook: ${limitOrderBookConfig.deployedAddress}`);
    console.log(`SwapWithLimitOrders: ${swapRouterConfig.deployedAddress}`);

    await verifyContracts(limitOrderBookConfig, swapRouterConfig);
    return;
  }

  // Verify required environment variables for deployment
  const requiredEnvVars = [
    "TURNKEY_API_PUBLIC_KEY",
    "TURNKEY_API_PRIVATE_KEY",
    "TURNKEY_ORGANIZATION_ID",
    "TURNKEY_PRIVATE_KEY_ID",
    "TURNKEY_TARGET_ADDRESS",
  ];

  for (const envVar of requiredEnvVars) {
    if (!process.env[envVar]) {
      throw new Error(`Missing required environment variable: ${envVar}`);
    }
  }

  // Create a Turnkey HTTP client with API key credentials
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    new ApiKeyStamper({
      apiPublicKey: process.env.TURNKEY_API_PUBLIC_KEY!,
      apiPrivateKey: process.env.TURNKEY_API_PRIVATE_KEY!,
    }),
  );

  // Create the Viem custom account
  console.log("Creating Turnkey account...");
  const turnkeyAccount = await createAccount({
    client: httpClient as any,
    organizationId: process.env.TURNKEY_ORGANIZATION_ID!,
    signWith: process.env.TURNKEY_PRIVATE_KEY_ID!,
    ethereumAddress: process.env.TURNKEY_TARGET_ADDRESS!,
  });

  console.log(`Turnkey account address: ${turnkeyAccount.address}\n`);

  // Get RPC URL for Base
  const rpcUrl = getRpcUrl("base");
  console.log(`Using RPC: ${rpcUrl}\n`);

  // Create wallet client
  const walletClient = createWalletClient({
    account: turnkeyAccount,
    chain: base,
    transport: http(rpcUrl),
  }).extend(publicActions);

  console.log(`\n=== Preparing Deployment ===`);
  console.log(`ZoraLimitOrderBook: ${limitOrderBookConfig.deployedAddress}`);
  console.log(`SwapWithLimitOrders: ${swapRouterConfig.deployedAddress}`);

  const dryRun = isDryRun();
  if (dryRun) {
    console.log("\n⚠️  DRY RUN MODE - No transactions will be sent");
  }

  // Simulate both deployments in one call
  console.log("\n=== Simulating Deployments ===");
  let limitOrderBookRequest, swapRouterRequest;
  try {
    const { request: limitOrderBookReq, result: limitOrderBookResult } =
      await walletClient.simulateContract({
        account: turnkeyAccount,
        address: IMMUTABLE_CREATE2_FACTORY,
        abi: IMMUTABLE_CREATE2_FACTORY_ABI,
        functionName: "safeCreate2",
        args: [limitOrderBookConfig.salt, limitOrderBookConfig.creationCode],
      });
    limitOrderBookRequest = limitOrderBookReq;

    console.log("✅ ZoraLimitOrderBook simulation successful");
    console.log(`   Result: ${limitOrderBookResult}`);
    console.log(`   Expected: ${limitOrderBookConfig.deployedAddress}`);
    if (
      limitOrderBookResult.toLowerCase() !==
      limitOrderBookConfig.deployedAddress.toLowerCase()
    ) {
      throw new Error(
        `Address mismatch! Simulated: ${limitOrderBookResult}, Expected: ${limitOrderBookConfig.deployedAddress}`,
      );
    }

    const { request: swapRouterReq, result: swapRouterResult } =
      await walletClient.simulateContract({
        account: turnkeyAccount,
        address: IMMUTABLE_CREATE2_FACTORY,
        abi: IMMUTABLE_CREATE2_FACTORY_ABI,
        functionName: "safeCreate2",
        args: [swapRouterConfig.salt, swapRouterConfig.creationCode],
      });
    swapRouterRequest = swapRouterReq;

    console.log("\n✅ SwapWithLimitOrders simulation successful");
    console.log(`   Result: ${swapRouterResult}`);
    console.log(`   Expected: ${swapRouterConfig.deployedAddress}`);
    if (
      swapRouterResult.toLowerCase() !==
      swapRouterConfig.deployedAddress.toLowerCase()
    ) {
      throw new Error(
        `Address mismatch! Simulated: ${swapRouterResult}, Expected: ${swapRouterConfig.deployedAddress}`,
      );
    }

    console.log("\n✅ All simulations passed!");
  } catch (error) {
    console.error("❌ Simulation failed:", error);
    throw error;
  }

  if (dryRun) {
    console.log("\n=== Dry Run Complete ===");
    console.log("No transactions were sent.");
    console.log("Run without --dry-run flag to deploy for real.");
    return;
  }

  // Deploy both contracts sequentially
  console.log("\n=== Deploying ZoraLimitOrderBook ===");
  const limitOrderBookHash = await walletClient.writeContract(
    limitOrderBookRequest,
  );
  console.log(`Transaction hash: ${limitOrderBookHash}`);
  console.log("Waiting for confirmation...");
  const limitOrderBookReceipt = await walletClient.waitForTransactionReceipt({
    hash: limitOrderBookHash,
  });
  console.log(
    `✅ Deployed at block ${limitOrderBookReceipt.blockNumber}, Gas used: ${limitOrderBookReceipt.gasUsed}`,
  );

  // Verify first deployment succeeded before continuing
  if (limitOrderBookReceipt.status !== "success") {
    throw new Error(
      `ZoraLimitOrderBook deployment failed with status: ${limitOrderBookReceipt.status}`,
    );
  }

  console.log("\n=== Deploying SwapWithLimitOrders ===");
  const swapRouterHash = await walletClient.writeContract(swapRouterRequest);
  console.log(`Transaction hash: ${swapRouterHash}`);
  console.log("Waiting for confirmation...");
  const swapRouterReceipt = await walletClient.waitForTransactionReceipt({
    hash: swapRouterHash,
  });
  console.log(
    `✅ Deployed at block ${swapRouterReceipt.blockNumber}, Gas used: ${swapRouterReceipt.gasUsed}`,
  );

  // Verify second deployment succeeded
  if (swapRouterReceipt.status !== "success") {
    throw new Error(
      `SwapWithLimitOrders deployment failed with status: ${swapRouterReceipt.status}`,
    );
  }

  console.log("\n=== Deployment Complete ===");
  console.log(`✅ Both contracts deployed successfully`);
  console.log(`ZORA_LIMIT_ORDER_BOOK: ${limitOrderBookConfig.deployedAddress}`);
  console.log(`ZORA_ROUTER: ${swapRouterConfig.deployedAddress}`);

  // Automatically verify contracts after deployment
  console.log("\n=== Verifying Contracts ===");

  try {
    await verifyContract(
      limitOrderBookConfig.deployedAddress,
      "ZoraLimitOrderBook",
      "base",
      limitOrderBookConfig.constructorArgs,
    );

    await verifyContract(
      swapRouterConfig.deployedAddress,
      "SwapWithLimitOrders",
      "base",
      swapRouterConfig.constructorArgs,
    );

    console.log("\n✅ Verification complete");
  } catch (error) {
    console.error("\n⚠️  Verification failed, but deployment was successful");
    console.error("You can verify manually later using:");
    console.error(
      `  forge verify-contract ${limitOrderBookConfig.deployedAddress} ZoraLimitOrderBook --constructor-args ${limitOrderBookConfig.constructorArgs} $(chains base --deploy)`,
    );
    console.error(
      `  forge verify-contract ${swapRouterConfig.deployedAddress} SwapWithLimitOrders --constructor-args ${swapRouterConfig.constructorArgs} $(chains base --deploy)`,
    );
  }
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
