import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { getPrivateKey, savePrivateKey, getWalletPath } from "./config.js";
import { outputErrorAndExit } from "./output.js";
import { selectOrDefault, passwordOrFail, confirmOrDefault } from "./prompt.js";
import { SAVE_ERROR_HINT } from "./strings.js";
import { normalizeKey } from "./wallet.js";
import { formatError } from "./errors.js";

export type WalletSetupResult =
  | { action: "created" | "imported"; address: string; path: string }
  | { action: "env_detected"; address: string }
  | { action: "skipped"; address: string; warning: string };

export interface WalletSetupOptions {
  json: boolean;
  nonInteractive: boolean;
  create?: boolean;
  force?: boolean;
  promptOverwrite?: boolean;
}

const isValidPrivateKey = (key: string): boolean =>
  /^(0x)?[0-9a-fA-F]{64}$/.test(key);

const toAccount = (json: boolean, key: string, errorPrefix: string) => {
  try {
    return privateKeyToAccount(normalizeKey(key));
  } catch {
    return outputErrorAndExit(
      json,
      `\u2717 ${errorPrefix} isn't a valid private key.`,
    );
  }
};

const walletExistsWarning = (truncated: string) =>
  `Wallet already configured: ${truncated}. Make sure your wallet is backed up \u2014 Zora is not responsible for any loss of funds.`;

export async function configureWallet(
  opts: WalletSetupOptions,
): Promise<WalletSetupResult> {
  const { json, nonInteractive, promptOverwrite } = opts;

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
    return { action: "env_detected", address: account.address };
  }

  let existing: string | undefined;
  if (!opts.force) {
    try {
      existing = getPrivateKey();
    } catch (err) {
      outputErrorAndExit(
        json,
        `\u2717 Could not read wallet: ${formatError(err)}`,
        "Run 'zora setup --force' to overwrite it.",
      );
    }
  }

  if (existing) {
    const account = toAccount(json, existing, "Stored private key");
    const truncated = `${account.address.slice(0, 6)}\u2026${account.address.slice(-4)}`;
    const warning = walletExistsWarning(truncated);

    if (promptOverwrite) {
      if (nonInteractive) {
        return { action: "skipped", address: account.address, warning };
      }
      const overwrite = await confirmOrDefault(
        { message: "Overwrite wallet configuration?", default: false },
        false,
      );
      if (!overwrite) {
        return { action: "skipped", address: account.address, warning };
      }
    } else {
      if (!opts.force) {
        outputErrorAndExit(
          json,
          `${warning}\nWallet already exists.`,
          "Use --force to overwrite.",
        );
      }
    }
  }

  let choice: "create" | "import";

  if (opts.create) {
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

    return {
      action: "imported",
      address: account.address,
      path: getWalletPath(),
    };
  }

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

  return {
    action: "created",
    address: account.address,
    path: getWalletPath(),
  };
}
