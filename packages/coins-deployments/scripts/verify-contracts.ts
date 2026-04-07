#!/usr/bin/env npx tsx
import { readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import * as chains from "viem/chains";
import { Address, encodeAbiParameters, Abi, AbiParameter } from "viem";
import { verifyContract } from "./lib/verify";
import { globSync } from "glob";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Build chain name to ID map from viem/chains
const chainIds: Record<string, number> = {};
for (const [name, chain] of Object.entries(chains)) {
  if (typeof chain === "object" && chain !== null && "id" in chain) {
    chainIds[name] = chain.id as number;
  }
}

interface Transaction {
  transactionType: string;
  contractName: string;
  contractAddress: string;
  arguments?: string[];
}

interface BroadcastFile {
  transactions: Transaction[];
}

interface CompiledContract {
  abi: Abi;
}

// Find the constructor ABI from a compiled contract
function getConstructorAbi(contractName: string): AbiParameter[] {
  // Try to find the contract's compiled output
  const outDir = join(__dirname, "..", "out");
  const pattern = `${outDir}/**/${contractName}.json`;

  console.log(`Looking for contract: ${contractName}`);
  console.log(`Pattern: ${pattern}`);

  const matches = globSync(pattern);

  console.log(`Matches found: ${matches.length}`);
  if (matches.length > 0) {
    console.log(`First match: ${matches[0]}`);
  }

  if (matches.length === 0) {
    throw new Error(
      `Could not find compiled contract for ${contractName} in ${outDir}`,
    );
  }

  const compiledPath = matches[0];
  const compiled: CompiledContract = JSON.parse(
    readFileSync(compiledPath, "utf-8"),
  );

  // Find constructor using the same approach as viem's encodeDeployData
  const constructor = compiled.abi.find(
    (x) => "type" in x && x.type === "constructor",
  );

  if (!constructor) {
    throw new Error(`No constructor found in ABI for ${contractName}`);
  }

  if (!("inputs" in constructor)) {
    throw new Error(`Constructor has no inputs field for ${contractName}`);
  }

  console.log(
    `Found constructor with ${constructor.inputs.length} inputs for ${contractName}`,
  );

  return constructor.inputs;
}

// Parse and convert constructor arguments based on ABI types
function parseConstructorArgs(
  args: string[],
  abiInputs: AbiParameter[],
): any[] {
  return args.map((arg, i) => {
    const abiType = abiInputs[i].type;

    // Handle array types
    if (abiType.endsWith("[]")) {
      // Parse the string representation of an array
      // e.g., "[0xAddr1, 0xAddr2]" -> ["0xAddr1", "0xAddr2"]
      const cleaned = arg.replace(/[\[\]]/g, "");
      if (!cleaned) return [];
      return cleaned.split(",").map((addr) => addr.trim());
    }

    // Return as-is for address and other types
    return arg;
  });
}

async function main() {
  const args = process.argv.slice(2);
  const [script, chain, ...flags] = args;

  // Check for --dev flag
  const isDev = flags.includes("--dev");

  if (!script || !chain) {
    console.error(
      "Usage: npx tsx verify-contracts.ts <script> <chain> [--dev]",
    );
    console.error(
      "Example: npx tsx verify-contracts.ts UpgradeCoinImpl.sol base",
    );
    console.error(
      "Example: npx tsx verify-contracts.ts UpgradeCoinImpl.sol base --dev",
    );
    process.exit(1);
  }

  const chainId = chainIds[chain];
  if (!chainId) {
    console.error(
      `Unknown chain: ${chain}. Some common chains: base, mainnet, sepolia, baseSepolia, zora, zoraSepolia`,
    );
    process.exit(1);
  }

  const broadcastPath = join(
    __dirname,
    "..",
    "broadcast",
    script,
    String(chainId),
    "run-latest.json",
  );
  console.log(`Reading broadcast file: ${broadcastPath}\n`);

  const broadcast: BroadcastFile = JSON.parse(
    readFileSync(broadcastPath, "utf-8"),
  );
  const creates = broadcast.transactions.filter(
    (tx) => tx.transactionType === "CREATE" || tx.transactionType === "CREATE2",
  );

  console.log(`Found ${creates.length} contracts to verify\n`);

  for (const tx of creates) {
    try {
      let constructorArgs: string | undefined;

      // Encode constructor arguments if present
      if (tx.arguments && tx.arguments.length > 0) {
        // Get the constructor ABI for this contract (throws if not found)
        const constructorAbi = getConstructorAbi(tx.contractName);

        if (constructorAbi.length !== tx.arguments.length) {
          throw new Error(
            `Constructor ABI has ${constructorAbi.length} inputs but ${tx.arguments.length} arguments were provided for ${tx.contractName}`,
          );
        }

        // Parse arguments based on ABI types
        const parsedArgs = parseConstructorArgs(tx.arguments, constructorAbi);

        // Encode using the proper types from the ABI
        const encodedArgs = encodeAbiParameters(constructorAbi, parsedArgs);

        // Remove 0x prefix for forge verify-contract
        constructorArgs = encodedArgs.slice(2);

        console.log(
          `Encoded constructor args for ${tx.contractName}: 0x${constructorArgs}\n`,
        );
      }

      await verifyContract(
        tx.contractAddress as Address,
        tx.contractName,
        chain,
        constructorArgs,
      );
    } catch (error) {
      console.error(`Failed to verify ${tx.contractName}:`, error, "\n");
    }
  }
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
