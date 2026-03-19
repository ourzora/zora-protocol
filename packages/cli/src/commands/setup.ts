import { Command } from "commander";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { savePrivateKey, getPrivateKey, getWalletPath } from "../lib/config.js";
import {
  getJson,
  getYes,
  outputErrorAndExit,
  outputData,
} from "../lib/output.js";
import { selectOrDefault, passwordOrFail } from "../lib/prompt.js";
import {
  DEPOSIT_INSTRUCTIONS,
  SAVE_ERROR_HINT,
  BACKUP_WARNING,
} from "../lib/strings.js";

const isValidPrivateKey = (key: string): boolean =>
  /^(0x)?[0-9a-fA-F]{64}$/.test(key);

const normalizeKey = (key: string): `0x${string}` =>
  (key.startsWith("0x") ? key : `0x${key}`) as `0x${string}`;

const toAccount = (json: boolean, key: string, errorPrefix: string) => {
  try {
    return privateKeyToAccount(normalizeKey(key));
  } catch {
    outputErrorAndExit(
      json,
      `\u2717 ${errorPrefix} isn't a valid private key.`,
    );
  }
};

export const setupCommand = new Command("setup")
  .description("Set up your Zora wallet")
  .option("--create", "Create a new wallet without prompting")
  .option("--force", "Overwrite existing wallet without prompting")
  .action(async function (
    this: Command,
    options: { create?: boolean; force?: boolean },
  ) {
    const json = getJson(this);
    const nonInteractive = getYes(this);

    const envKey = process.env.ZORA_PRIVATE_KEY;
    if (envKey !== undefined) {
      if (!isValidPrivateKey(envKey)) {
        outputErrorAndExit(
          json,
          "\u2717 ZORA_PRIVATE_KEY isn't a valid private key.",
          "Fix it and run zora setup again.",
        );
      }
      const account = toAccount(json, envKey, "ZORA_PRIVATE_KEY");
      outputData(json, {
        json: { source: "env", address: account.address },
        table: () => {
          console.log("  Using wallet from ZORA_PRIVATE_KEY.\n");
          console.log(`  Address: ${account.address}\n`);
          console.log(`  ${DEPOSIT_INSTRUCTIONS}`);
        },
      });
      return;
    }

    let existing: string | undefined;
    if (!options.force) {
      try {
        existing = getPrivateKey();
      } catch (err) {
        outputErrorAndExit(
          json,
          `\u2717 Could not read wallet: ${(err as Error).message}`,
          "Run 'zora setup --force' to overwrite it.",
        );
      }
    }
    if (existing) {
      const account = toAccount(json, existing, "Stored private key");
      const truncated = `${account.address.slice(0, 6)}\u2026${account.address.slice(-4)}`;
      console.log(`  Wallet already configured: ${truncated}\n`);
      if (!options.force) {
        outputErrorAndExit(
          json,
          "Wallet already exists.",
          "Use --force to overwrite.",
        );
      }
    }

    let choice: "create" | "import";

    if (options.create) {
      choice = "create";
    } else {
      choice = await selectOrDefault(
        {
          message: "How do you want to set up your wallet?",
          choices: [
            {
              name: "Create a new wallet (recommended)",
              value: "create" as const,
            },
            { name: "Import a private key", value: "import" as const },
          ],
          default: "create" as const,
        },
        nonInteractive,
      );
    }

    if (choice === "import") {
      let importedKey: string | undefined;
      while (!importedKey) {
        const input = await passwordOrFail(
          json,
          { message: "Paste your private key:" },
          nonInteractive,
        );
        if (isValidPrivateKey(input.trim())) {
          importedKey = input.trim();
        } else {
          console.error(
            "\u2717 Not a valid private key. Must be 64 hex characters, with or without a 0x prefix.\n",
          );
        }
      }

      const account = toAccount(json, importedKey, "Imported key");

      try {
        savePrivateKey(importedKey);
      } catch {
        outputErrorAndExit(
          json,
          `\u2717 Couldn't save to ${getWalletPath()}.`,
          SAVE_ERROR_HINT,
        );
      }

      outputData(json, {
        json: {
          action: "imported",
          address: account.address,
          path: getWalletPath(),
        },
        table: () => {
          console.log("\n\u2713 Wallet imported\n");
          console.log(`  Address:     ${account.address}`);
          console.log(`  Private key: saved to ${getWalletPath()}\n`);
          console.log(`  ${BACKUP_WARNING}\n`);
          console.log(`  ${DEPOSIT_INSTRUCTIONS}`);
        },
      });
      return;
    }

    if (choice === "create") {
      const privateKey = generatePrivateKey();
      const account = toAccount(json, privateKey, "Generated key");

      try {
        savePrivateKey(privateKey);
      } catch {
        outputErrorAndExit(
          json,
          `\u2717 Couldn't save to ${getWalletPath()}.`,
          SAVE_ERROR_HINT,
        );
      }

      outputData(json, {
        json: {
          action: "created",
          address: account.address,
          path: getWalletPath(),
        },
        table: () => {
          console.log("\n\u2713 Wallet created\n");
          console.log(`  Address:     ${account.address}`);
          console.log(`  Private key: saved to ${getWalletPath()}\n`);
          console.log(`  ${BACKUP_WARNING}\n`);
          console.log(`  ${DEPOSIT_INSTRUCTIONS}`);
        },
      });
    }
  });
