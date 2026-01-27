#!/usr/bin/env npx tsx
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import * as chains from "viem/chains";
import { Address, encodeAbiParameters } from "viem";
import { verifyContract } from "./lib/verify";

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

async function main() {
  const [script, chain] = process.argv.slice(2);

  if (!script || !chain) {
    console.error("Usage: npx tsx verify-contracts.ts <script> <chain>");
    console.error(
      "Example: npx tsx verify-contracts.ts UpgradeCoinImpl.sol base",
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
    (tx) => tx.transactionType === "CREATE",
  );

  console.log(`Found ${creates.length} contracts to verify\n`);

  for (const tx of creates) {
    try {
      let constructorArgs: string | undefined;

      // Encode constructor arguments if present
      if (tx.arguments && tx.arguments.length > 0) {
        const encodedArgs = encodeAbiParameters(
          tx.arguments.map(() => ({ type: "address" })),
          tx.arguments as Address[],
        );
        // Remove 0x prefix for forge verify-contract
        constructorArgs = encodedArgs.slice(2);
      }

      await verifyContract(
        tx.contractAddress as Address,
        tx.contractName,
        chain,
        constructorArgs,
      );
    } catch {
      console.error(`Failed to verify ${tx.contractName}\n`);
    }
  }
}

main().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
