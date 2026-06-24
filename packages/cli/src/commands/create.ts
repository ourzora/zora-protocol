import { Command } from "commander";
import confirm from "@inquirer/confirm";
import input from "@inquirer/input";
import select from "@inquirer/select";
import { existsSync, readFileSync } from "node:fs";
import { basename, extname } from "node:path";
import { base } from "viem/chains";
import type { Address } from "viem";
import {
  createCoin,
  createCoinSmartWallet,
  createMetadataBuilder,
  createZoraUploaderForCreator,
  CreateConstants,
  setApiKey,
  type ContentCoinCurrency,
} from "@zoralabs/coins-sdk";
import { resolveAccounts, createClients } from "../lib/wallet.js";
import { getApiKey } from "../lib/config.js";
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import { safeExit, SUCCESS } from "../lib/exit.js";
import { track, shutdownAnalytics } from "../lib/analytics.js";
import { gasErrorSuggestion } from "../lib/gas.js";
import { validateTicker } from "../lib/ticker.js";
import { serializeError } from "../lib/errors.js";

/** Image extensions accepted by the metadata uploader, mapped to their MIME type. */
const IMAGE_MIME_BY_EXT: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
};

const VALID_CURRENCIES = CreateConstants.ContentCoinCurrencies;

/** Human-friendly labels for each backing currency, shown in the select prompt. */
const CURRENCY_CHOICES: { name: string; value: ContentCoinCurrency }[] = [
  { name: "ZORA", value: VALID_CURRENCIES.ZORA },
  { name: "ETH", value: VALID_CURRENCIES.ETH },
  { name: "Creator Coin", value: VALID_CURRENCIES.CREATOR_COIN },
  {
    name: "Creator Coin or ZORA",
    value: VALID_CURRENCIES.CREATOR_COIN_OR_ZORA,
  },
];

const DEFAULT_CURRENCY: ContentCoinCurrency = VALID_CURRENCIES.ZORA;

/**
 * Resolves the backing currency. When provided via --currency it is validated;
 * otherwise the user picks from a select prompt. In --json (non-interactive)
 * mode an unspecified currency falls back to the default rather than prompting.
 */
async function resolveCurrency(
  raw: string | undefined,
  json: boolean,
): Promise<ContentCoinCurrency> {
  if (raw !== undefined) {
    const key = raw.toUpperCase();
    if (!(key in VALID_CURRENCIES)) {
      return outputErrorAndExit(
        json,
        `Invalid --currency value: ${raw}`,
        "Use one of: ZORA, ETH, CREATOR_COIN, CREATOR_COIN_OR_ZORA",
      );
    }
    return key as ContentCoinCurrency;
  }

  if (json) return DEFAULT_CURRENCY;

  return select({
    message: "Currency (paired with)",
    choices: CURRENCY_CHOICES,
    default: DEFAULT_CURRENCY,
  });
}

/**
 * Returns the option value if present, otherwise prompts the user. In --json
 * (non-interactive) mode there is nothing to prompt with, so a missing required
 * value is a hard error instead.
 */
async function resolveField(
  value: string | undefined,
  {
    json,
    message,
    flag,
    required = true,
  }: { json: boolean; message: string; flag: string; required?: boolean },
): Promise<string> {
  if (value !== undefined) return value;
  if (json) {
    // Prompts are disabled in --json mode: optional fields default to empty,
    // required fields are a hard error.
    if (!required) return "";
    return outputErrorAndExit(
      json,
      `Missing ${flag} in --json mode.`,
      `Pass ${flag} when using --json (prompts are disabled).`,
    );
  }
  return input({ message, required });
}

export const createCommand = new Command("create")
  .description("Create a coin (post)")
  .option("--name <name>", "Coin name")
  .option("--symbol <symbol>", "Coin symbol (ticker)")
  .option("--description <description>", "Coin description")
  .option("--image <path>", "Path to a local image file to upload")
  .option(
    "--currency <currency>",
    "Backing currency: ZORA, ETH, CREATOR_COIN, CREATOR_COIN_OR_ZORA (prompts if omitted)",
  )
  .option("--yes", "Skip confirmation and create directly")
  .action(async function (
    this: Command,
    opts: {
      name?: string;
      symbol?: string;
      description?: string;
      image?: string;
      currency?: string;
      yes?: boolean;
    },
  ) {
    const json = getJson(this);

    // Uploading metadata to Zora's IPFS uploader requires an API key.
    const apiKey = getApiKey();
    if (!apiKey) {
      return outputErrorAndExit(
        json,
        "An API key is required to create a coin.",
        "Run 'zora auth configure' to set your API key.",
      );
    }
    setApiKey(apiKey);

    // Collect coin details, prompting for any not provided on the command line.
    const name = await resolveField(opts.name, {
      json,
      message: "Coin name:",
      flag: "--name",
    });
    const symbol = await resolveField(opts.symbol, {
      json,
      message: "Coin symbol (ticker):",
      flag: "--symbol",
    });

    // Reject a ticker the platform would refuse (too short/long, or with
    // disallowed characters) before uploading metadata or touching the chain.
    const tickerError = validateTicker(symbol);
    if (tickerError) {
      return outputErrorAndExit(json, tickerError, "Pass a valid --symbol.");
    }
    const description = await resolveField(opts.description, {
      json,
      message: "Description (optional):",
      flag: "--description",
      required: false,
    });
    const imagePath = await resolveField(opts.image, {
      json,
      message: "Path to image file:",
      flag: "--image",
    });
    const currency = await resolveCurrency(opts.currency, json);

    // Verify the image exists and is a supported type before doing any work.
    if (!existsSync(imagePath)) {
      return outputErrorAndExit(
        json,
        `Image file not found: ${imagePath}`,
        "Provide a path to an existing local image file.",
      );
    }

    const ext = extname(imagePath).toLowerCase();
    const mimeType = IMAGE_MIME_BY_EXT[ext];
    if (!mimeType) {
      return outputErrorAndExit(
        json,
        `Unsupported image type: ${ext || "(no extension)"}`,
        "Supported types: PNG, JPEG, JPG, GIF, SVG.",
      );
    }

    // Prefer the smart wallet path when one is configured, otherwise use the EOA.
    const { privateKeyAccount, smartWalletAccount } = await resolveAccounts();
    const { publicClient, walletClient, bundlerClient } = createClients(
      privateKeyAccount,
      smartWalletAccount,
    );

    const creator: Address =
      smartWalletAccount?.address ?? privateKeyAccount.address;
    const usingSmartWallet = !!smartWalletAccount;

    if (usingSmartWallet && !bundlerClient) {
      return outputErrorAndExit(
        json,
        "Failed to obtain bundler client for your smart wallet. Please try again. If the problem persists, ensure your smart wallet is setup correctly.",
      );
    }

    if (!opts.yes && !json) {
      console.log(`\n Create coin\n`);
      console.log(`   Name         ${name}`);
      console.log(`   Symbol       ${symbol}`);
      if (description) {
        console.log(`   Description  ${description}`);
      }
      console.log(`   Image        ${imagePath}`);
      console.log(`   Currency     ${currency}`);
      console.log(
        `   Creator      ${creator} (${usingSmartWallet ? "smart wallet" : "EOA"})`,
      );
      console.log("");

      const ok = await confirm({ message: "Confirm?", default: false });
      if (!ok) {
        console.error("Aborted.");
        return safeExit(SUCCESS);
      }
    }

    // Upload the image and metadata to IPFS.
    let metadataParams;
    try {
      const imageFile = new File(
        [readFileSync(imagePath)],
        basename(imagePath),
        {
          type: mimeType,
        },
      );

      const builder = createMetadataBuilder()
        .withName(name)
        .withSymbol(symbol)
        .withImage(imageFile);

      if (description) {
        builder.withDescription(description);
      }

      const { createMetadataParameters } = await builder.upload(
        createZoraUploaderForCreator(creator),
      );
      metadataParams = createMetadataParameters;
    } catch (err) {
      track("cli_create", {
        currency,
        wallet_type: usingSmartWallet ? "smart_wallet" : "eoa",
        output_format: json ? "json" : "static",
        success: false,
        stage: "upload",
        error_type: err instanceof Error ? err.constructor.name : "unknown",
        error_message: err instanceof Error ? err.message : String(err),
        error: serializeError(err),
      });
      await shutdownAnalytics();
      return outputErrorAndExit(
        json,
        `Failed to upload metadata: ${err instanceof Error ? err.message : String(err)}`,
      );
    }

    // Deploy the coin via the appropriate wallet path.
    let result: Awaited<
      ReturnType<typeof createCoin | typeof createCoinSmartWallet>
    >;
    try {
      const call = {
        creator,
        name: metadataParams.name,
        symbol: metadataParams.symbol,
        metadata: metadataParams.metadata,
        currency,
        chainId: base.id,
      };

      result = usingSmartWallet
        ? await createCoinSmartWallet({
            call,
            bundlerClient: bundlerClient!,
            publicClient,
          })
        : await createCoin({
            call,
            walletClient,
            publicClient,
            options: { account: privateKeyAccount },
          });
    } catch (err) {
      track("cli_create", {
        currency,
        wallet_type: usingSmartWallet ? "smart_wallet" : "eoa",
        output_format: json ? "json" : "static",
        success: false,
        stage: "deploy",
        error_type: err instanceof Error ? err.constructor.name : "unknown",
        error_message: err instanceof Error ? err.message : String(err),
        error: serializeError(err),
      });
      await shutdownAnalytics();
      return outputErrorAndExit(
        json,
        `Failed to create coin: ${err instanceof Error ? err.message : String(err)}`,
        gasErrorSuggestion(err, smartWalletAccount ?? privateKeyAccount),
      );
    }

    const coinAddress = result.address ?? null;
    const txHash = result.hash ?? null;

    if (json) {
      outputJson({
        action: "create",
        name,
        symbol,
        currency,
        address: coinAddress,
        creator,
        walletType: usingSmartWallet ? "smart_wallet" : "eoa",
        tx: txHash,
      });
    } else {
      console.log(`\n Created ${name} (${symbol})\n`);
      console.log(`   Address      ${coinAddress ?? "unknown"}`);
      console.log(`   Tx           ${txHash ?? "unknown"}\n`);
    }

    track("cli_create", {
      currency,
      coin_address: coinAddress,
      coin_name: name,
      coin_symbol: symbol,
      wallet_type: usingSmartWallet ? "smart_wallet" : "eoa",
      transactionHash: txHash,
      output_format: json ? "json" : "static",
      success: true,
      tx_hash: txHash,
    });
  });
