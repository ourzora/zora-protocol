import { execSync } from "child_process";
import { Address } from "viem";

/**
 * Verify a contract on the block explorer using forge verify-contract
 * @param contractAddress The deployed contract address
 * @param contractName The contract name (must match the contract in the codebase)
 * @param chainName The chain name from viem/chains (e.g., "base", "mainnet", "sepolia")
 * @param constructorArgs Optional hex-encoded constructor arguments (if not provided, uses --guess-constructor-args)
 * @returns Promise that resolves when verification completes or rejects on error
 */
export async function verifyContract(
  contractAddress: Address,
  contractName: string,
  chainName: string,
  constructorArgs?: string,
): Promise<void> {
  console.log(`\n=== Verifying ${contractName} at ${contractAddress} ===`);
  try {
    const argsFlag = constructorArgs
      ? `--constructor-args ${constructorArgs}`
      : "--guess-constructor-args";
    const cmd = `forge verify-contract ${contractAddress} ${contractName} ${argsFlag} $(chains ${chainName} --deploy)`;
    console.log(`Running: ${cmd}`);
    execSync(cmd, { stdio: "inherit", shell: "/bin/bash" });
    console.log(`✅ ${contractName} verified`);
  } catch (error) {
    console.error(`❌ Failed to verify ${contractName}`);
    throw error;
  }
}
