import { Command } from "commander";
import {
  getApiKey,
  getEnvApiKey,
  saveApiKey,
  getConfigPath,
} from "../lib/config.js";
import { maskKey } from "../lib/mask-key.js";
import {
  getJson,
  getYes,
  outputErrorAndExit,
  outputData,
} from "../lib/output.js";
import { passwordOrFail } from "../lib/prompt.js";

export const authCommand = new Command("auth").description(
  "Manage API key authentication.\nAPI key is optional — without one, requests are rate-limited.\nGet a key at https://zora.co/settings/developer",
);

authCommand
  .command("configure")
  .description("Set your Zora API key")
  .action(async function (this: Command) {
    const json = getJson(this);
    const nonInteractive = getYes(this);

    if (getEnvApiKey()) {
      outputData(json, {
        json: {
          status: "env_override",
          message: "API key is set via ZORA_API_KEY environment variable.",
        },
        table: () =>
          console.log(
            "API key is set via ZORA_API_KEY environment variable. Unset it to configure manually.",
          ),
      });
      return;
    }

    const existing = getApiKey();
    if (existing) {
      console.log(`Current key: ${maskKey(existing)}`);
    }

    console.log("Get your API key from: https://zora.co/settings/developer\n");

    const apiKey = await passwordOrFail(
      json,
      { message: "Paste your API key:" },
      nonInteractive,
    );

    const trimmed = apiKey.trim();
    if (!trimmed) {
      outputErrorAndExit(
        json,
        "No API key provided.",
        "Usage: zora auth configure",
      );
    }

    try {
      saveApiKey(trimmed);
      outputData(json, {
        json: { saved: true, path: getConfigPath() },
        table: () => console.log(`API key saved to ${getConfigPath()}`),
      });
    } catch (err) {
      outputErrorAndExit(
        json,
        `Failed to save API key: ${(err as Error).message}`,
      );
    }
  });

authCommand
  .command("status")
  .description("Check authentication status")
  .action(function (this: Command) {
    const json = getJson(this);
    const apiKey = getApiKey();

    if (!apiKey) {
      outputData(json, {
        json: { authenticated: false },
        table: () => {
          console.log(
            "No API key configured. The CLI works without one, but requests are rate-limited.",
          );
          console.log(
            "Run 'zora auth configure' to set an API key for higher rate limits.",
          );
        },
      });
      return;
    }

    const source = getEnvApiKey() ? "env (ZORA_API_KEY)" : getConfigPath();
    outputData(json, {
      json: { authenticated: true, key: maskKey(apiKey), source },
      table: () => {
        console.log(`Authenticated: ${maskKey(apiKey)}`);
        console.log(`Source: ${source}`);
      },
    });
  });
