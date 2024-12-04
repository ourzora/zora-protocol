#!/usr/bin/env tsx
import { promises as fs } from "fs";
import { join } from "pathe";

/**
 * This script fixes a breaking change introduced in wagmi/cli v1 -> v2 migration.
 * In v2, the CLI generates types with 'Abi' suffix (e.g., 'contractAbi'),
 * whereas v1 used 'ABI' (e.g., 'contractABI'). This casing difference would cause
 * breaking changes in consuming code, so we normalize it back to 'ABI'.
 */
export const renameGeneratedAbis = async (
  filePaths: string | string[],
  projectPath: string = process.cwd(),
) => {
  // Ensure we're working with an array of paths
  const paths = Array.isArray(filePaths) ? filePaths : [filePaths];

  console.log(
    `🔄 Processing ${paths.length} file(s) to replace 'Abi' with 'ABI'...`,
  );

  await Promise.all(
    paths.map(async (filePath) => {
      const fullPath = join(projectPath, filePath);
      console.log(`📝 Processing ${filePath}...`);

      let content = await fs.readFile(fullPath, "utf-8");

      // Count occurrences of word-ending 'Abi'
      // e.g., 'contractAbi' but not 'AbiEncoder'
      const matches = content.match(/\w+Abi\b/g)?.length || 0;

      // Replace all word-ending 'Abi' with 'ABI'
      // Uses capture group ($1) to maintain the prefix
      // e.g., 'contractAbi' -> 'contractABI'
      content = content.replace(/(\w+)Abi\b/g, "$1ABI");

      await fs.writeFile(fullPath, content);
      console.log(`✅ Updated ${filePath} (${matches} replacements)`);
    }),
  );

  console.log("✨ All files processed successfully!");
};

// Allow script to be run directly from command line
const isMainModule = import.meta.url.startsWith("file:");
if (isMainModule) {
  const filePaths = process.argv.slice(2);
  if (filePaths.length === 0) {
    console.error("Please provide at least one file path as an argument");
    process.exit(1);
  }
  renameGeneratedAbis(filePaths).catch(console.error);
}
