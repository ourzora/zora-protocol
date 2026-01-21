#!/usr/bin/env npx tsx
import { readFileSync } from "fs";
import { execSync } from "child_process";
import { join } from "path";

// Map chain names to chain IDs
const chainIds: Record<string, string> = {
  base: "8453",
  mainnet: "1",
  sepolia: "11155111",
  "base-sepolia": "84532",
  zora: "7777777",
  "zora-sepolia": "999999999",
};

interface Transaction {
  transactionType: string;
  contractName: string;
  contractAddress: string;
}

interface BroadcastFile {
  transactions: Transaction[];
}

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
    `Unknown chain: ${chain}. Known chains: ${Object.keys(chainIds).join(", ")}`,
  );
  process.exit(1);
}

const broadcastPath = join("broadcast", script, chainId, "run-latest.json");
console.log(`Reading broadcast file: ${broadcastPath}\n`);

const broadcast: BroadcastFile = JSON.parse(
  readFileSync(broadcastPath, "utf-8"),
);
const creates = broadcast.transactions.filter(
  (tx) => tx.transactionType === "CREATE",
);

console.log(`Found ${creates.length} contracts to verify\n`);

for (const tx of creates) {
  console.log(`Verifying ${tx.contractName} at ${tx.contractAddress}...`);
  try {
    const cmd = `forge verify-contract ${tx.contractAddress} ${tx.contractName} --guess-constructor-args $(chains ${chain} --deploy)`;
    console.log(`  Running: ${cmd}`);
    execSync(cmd, { stdio: "inherit", shell: "/bin/bash" });
    console.log(`  ✓ ${tx.contractName} verified\n`);
  } catch {
    console.error(`  ✗ Failed to verify ${tx.contractName}\n`);
  }
}
