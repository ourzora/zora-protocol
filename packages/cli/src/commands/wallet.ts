import { Command } from "commander";
import { privateKeyToAccount } from "viem/accounts";
import { getPrivateKey, getWalletPath } from "../lib/config.js";
import {
  getJson,
  getYes,
  outputErrorAndExit,
  outputData,
} from "../lib/output.js";
import { confirmOrDefault } from "../lib/prompt.js";
import {
  NO_WALLET_CONFIGURED,
  NO_WALLET_SUGGESTION,
  DEPOSIT_SOURCES,
  BACKUP_WARNING,
} from "../lib/strings.js";
import { normalizeKey } from "../lib/wallet.js";
import { track } from "../lib/analytics.js";
import { configureWallet } from "../lib/wallet-setup.js";

const resolvePrivateKey = ():
  | { key: string; source: "env" | "file" }
  | undefined => {
  const envKey = process.env.ZORA_PRIVATE_KEY;
  if (envKey) {
    return { key: envKey, source: "env" };
  }
  const fileKey = getPrivateKey();
  if (fileKey !== undefined) {
    return { key: fileKey, source: "file" };
  }
  return undefined;
};

export const walletCommand = new Command("wallet").description(
  "Manage your Zora wallet",
);

walletCommand
  .command("info")
  .description("Show wallet address and storage location")
  .action(function (this: Command) {
    const json = getJson(this);
    const resolved = resolvePrivateKey();

    if (!resolved) {
      outputErrorAndExit(json, NO_WALLET_CONFIGURED, NO_WALLET_SUGGESTION);
    }

    let account;
    try {
      account = privateKeyToAccount(normalizeKey(resolved.key));
    } catch {
      const msg =
        resolved.source === "env"
          ? "ZORA_PRIVATE_KEY is not a valid private key."
          : "Stored private key is invalid.";
      const suggestion =
        resolved.source === "env"
          ? undefined
          : "Run 'zora setup --force' to replace it.";
      outputErrorAndExit(json, `\u2717 ${msg}`, suggestion);
    }

    const source =
      resolved.source === "env" ? "env (ZORA_PRIVATE_KEY)" : getWalletPath();

    outputData(json, {
      json: { address: account.address, source },
      render: () => {
        console.log(`  Address: ${account.address}`);
        console.log(`  Source:  ${source}`);
      },
    });

    track("cli_wallet_info", {
      source: resolved.source,
      output_format: json ? "json" : "text",
    });
  });

walletCommand
  .command("export")
  .description("Print the raw private key to stdout")
  .option("--force", "Skip the confirmation prompt")
  .option("--yes", "Skip interactive prompt and execute directly")
  .action(async function (this: Command, options: { force?: boolean }) {
    const json = getJson(this);
    const nonInteractive = getYes(this);
    const resolved = resolvePrivateKey();

    if (!resolved) {
      outputErrorAndExit(json, NO_WALLET_CONFIGURED, NO_WALLET_SUGGESTION);
    }

    if (!options.force) {
      console.log(
        "  \u26a0  Your private key grants full access to your wallet.",
      );
      console.log(
        "  Anyone who sees it can steal your funds. Never share it.\n",
      );

      const ok = await confirmOrDefault(
        { message: "Export private key?", default: false },
        nonInteractive,
      );

      if (!ok) {
        console.error("Aborted.");
        process.exit(0);
      }
    }

    console.log(resolved.key);

    track("cli_wallet_export", {
      output_format: json ? "json" : "text",
    });
  });

walletCommand
  .command("configure")
  .description("Create or import a wallet")
  .option("--create", "Create a new wallet without prompting")
  .option("--force", "Overwrite existing wallet without prompting")
  .option("--yes", "Skip interactive prompt and execute directly")
  .action(async function (
    this: Command,
    options: { create?: boolean; force?: boolean },
  ) {
    const json = getJson(this);
    const nonInteractive = getYes(this);

    const result = await configureWallet({
      json,
      nonInteractive,
      create: options.create,
      force: options.force,
      promptOverwrite: false,
    });

    outputData(json, {
      json: result,
      render: () => {
        if (result.action === "env_detected") {
          console.log("  Using wallet from ZORA_PRIVATE_KEY.\n");
          console.log(`  Address: ${result.address}\n`);
          console.log(
            `  Deposit ETH or USDC on Base to start trading.\n\n  ${DEPOSIT_SOURCES}`,
          );
        } else if (
          result.action === "created" ||
          result.action === "imported"
        ) {
          const verb = result.action === "created" ? "created" : "imported";
          console.log(`\n\u2713 Wallet ${verb}\n`);
          console.log(`  Address:     ${result.address}`);
          console.log(`  Private key: saved to ${result.path}\n`);
          console.log(`  ${BACKUP_WARNING}\n`);
          console.log(
            `  Deposit ETH or USDC on Base to start trading.\n\n  ${DEPOSIT_SOURCES}`,
          );
        } else if (result.action === "skipped") {
          console.log(`  Wallet already configured: ${result.address}\n`);
        }
      },
    });

    track("cli_wallet_config", {
      action: result.action,
      output_format: json ? "json" : "text",
    });
  });
