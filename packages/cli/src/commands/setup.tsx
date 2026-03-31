import { Command } from "commander";
import { Text, Box } from "ink";
import {
  getApiKey,
  getEnvApiKey,
  saveApiKey,
  getConfigPath,
} from "../lib/config.js";
import {
  getJson,
  getYes,
  outputErrorAndExit,
  outputData,
} from "../lib/output.js";
import { confirmOrDefault, passwordOrSkip } from "../lib/prompt.js";
import { maskKey } from "../lib/mask-key.js";
import { DEPOSIT_SOURCES, BACKUP_WARNING } from "../lib/strings.js";
import { track } from "../lib/analytics.js";
import { configureWallet } from "../lib/wallet-setup.js";
import { fsErrorMessage } from "../lib/errors.js";
import { warningBox } from "../lib/warning-box.js";
import { renderOnce } from "../lib/render.js";
import { DIM, BOLD, RESET, useAnsi } from "../lib/ansi.js";

function stepLine(step: number, total: number, title: string) {
  const cols = (process.stdout.columns || 80) - 4;
  if (!useAnsi()) {
    console.log(`\n[${step}/${total}] ${title}`);
    console.log(`${"\u2500".repeat(Math.max(cols, 20))}\n`);
    return;
  }
  console.log(
    `\n${BOLD}${DIM}[${step}/${total}]${RESET} ${BOLD}${title}${RESET}`,
  );
  console.log(`${DIM}${"\u2500".repeat(Math.max(cols, 20))}${RESET}\n`);
}

export const setupCommand = new Command("setup")
  .description("Guided first-time setup")
  .option("--create", "Create a new wallet without prompting")
  .option("--force", "Overwrite existing wallet without prompting")
  .option("--yes", "Skip interactive prompt and execute directly")
  .action(async function (
    this: Command,
    options: { create?: boolean; force?: boolean },
  ) {
    const json = getJson(this);
    const nonInteractive = getYes(this);

    // ── [1/3] Wallet ──────────────────────────────────────────

    if (!json) stepLine(1, 3, "Set up wallet");

    const walletResult = await configureWallet({
      json,
      nonInteractive,
      create: options.create,
      force: options.force,
      promptOverwrite: true,
    });

    if (!json) {
      if (walletResult.action === "env_detected") {
        console.log("Using wallet from ZORA_PRIVATE_KEY.");
        console.log(`Address: ${walletResult.address}\n`);
      } else if (walletResult.action === "skipped") {
        warningBox(walletResult.warning);
        console.log(`${DIM}Keeping existing wallet.${RESET}\n`);
      } else {
        const verb = walletResult.action === "created" ? "created" : "imported";
        console.log(`\u2713 Wallet ${verb}`);
        console.log(`Address:     ${walletResult.address}`);
        console.log(`Private key: saved to ${walletResult.path}\n`);
        warningBox(BACKUP_WARNING);
      }
    }

    // ── [2/3] API key ─────────────────────────────────────────

    if (!json) stepLine(2, 3, "Set up API key (optional)");

    let apiKeyStatus: "saved" | "skipped" | "env_override" | "already_set";

    const envApiKey = getEnvApiKey();
    if (envApiKey) {
      apiKeyStatus = "env_override";
      if (!json) {
        console.log("API key is set via ZORA_API_KEY environment variable.\n");
      }
    } else {
      const existingKey = getApiKey();
      if (existingKey && !options.force) {
        if (nonInteractive) {
          apiKeyStatus = "already_set";
          if (!json) {
            console.log(
              `API key already configured: ${maskKey(existingKey)}\n`,
            );
          }
        } else {
          if (!json) console.log(`Current key: ${maskKey(existingKey)}`);
          const overwrite = await confirmOrDefault(
            { message: "Overwrite API key?", default: false },
            false,
          );
          if (!overwrite) {
            apiKeyStatus = "already_set";
            if (!json) console.log("");
          } else {
            apiKeyStatus = await promptAndSaveApiKey(json);
          }
        }
      } else {
        apiKeyStatus = await promptAndSaveApiKey(json, nonInteractive);
      }
    }

    // ── [3/3] Deposit ─────────────────────────────────────────

    if (!json) stepLine(3, 3, "Deposit");

    if (!json) {
      renderOnce(
        <Box
          flexDirection="column"
          borderStyle="single"
          borderDimColor
          paddingX={1}
          paddingY={1}
        >
          <Text>
            Your address: <Text bold>{walletResult.address}</Text>
          </Text>
          <Text>
            Deposit{" "}
            <Text bold color="blue">
              ETH or USDC on Base
            </Text>{" "}
            to start trading.
          </Text>
        </Box>,
      );
      console.log(`\n${DEPOSIT_SOURCES}\n`);
    }

    // ── Output ────────────────────────────────────────────────

    outputData(json, {
      json: { wallet: walletResult, apiKey: apiKeyStatus },
      render: () => {},
    });

    track("cli_setup", {
      wallet_action: walletResult.action,
      api_key_status: apiKeyStatus,
      output_format: json ? "json" : "text",
    });
  });

async function promptAndSaveApiKey(
  json: boolean,
  nonInteractive = false,
): Promise<"saved" | "skipped"> {
  if (!json && !nonInteractive) {
    console.log(
      "Optional. An API key unlocks higher rate limits for frequent trading.",
    );
    console.log("Get your API key from: https://zora.co/settings/developer\n");
  }

  const apiKey = await passwordOrSkip(
    { message: "Paste your API key (Enter to skip):" },
    nonInteractive,
  );

  const trimmed = apiKey.trim();
  if (!trimmed) {
    if (!json) console.log("Skipped API key configuration.\n");
    return "skipped";
  }

  try {
    saveApiKey(trimmed);
    if (!json) console.log(`API key saved to ${getConfigPath()}\n`);
    return "saved";
  } catch (err) {
    outputErrorAndExit(
      json,
      `Failed to save API key: ${fsErrorMessage(err, getConfigPath())}`,
    );
  }
}
