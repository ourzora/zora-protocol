import { Command } from "commander";
import confirm from "@inquirer/confirm";
import input from "@inquirer/input";
import { existsSync, readFileSync } from "node:fs";
import { basename, extname } from "node:path";
import { isAddress, type Address } from "viem";
import {
  createZoraUploaderForCreator,
  getCoin,
  setApiKey,
  updateCoinURI,
  updateCoinURISmartWallet,
} from "@zoralabs/coins-sdk";
import { track, shutdownAnalytics } from "../lib/analytics.js";
import { resolveAmbiguousName } from "../lib/coin-ref.js";
import { getApiKey, getPrivateKey } from "../lib/config.js";
import {
  fetchCoinMetadata,
  mergeMetadata,
  type CoinMetadata,
} from "../lib/edit.js";
import { formatError, serializeError } from "../lib/errors.js";
import { safeExit, SUCCESS } from "../lib/exit.js";
import { gasErrorSuggestion } from "../lib/gas.js";
import { imageMimeForPath } from "../lib/image.js";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";

export interface EditOptions {
  description?: string;
  image?: string;
  yes?: boolean;
}

/** A coin resolved for editing — the on-chain fields the edit flow needs. */
interface EditTarget {
  address: string;
  name: string;
  symbol: string;
  tokenUri: string;
  creatorAddress?: string;
}

/**
 * Turns a coin identifier (address, or a creator/trend name) into the coin's
 * on-chain metadata URI plus the labels we display. We always fetch the full
 * token via `getCoin` (not just `resolveCoin`) because the edit needs the
 * current `tokenUri` to preserve the fields we aren't changing.
 */
async function resolveEditTarget(
  json: boolean,
  identifier: string,
): Promise<EditTarget> {
  let address = identifier;
  if (!isAddress(identifier)) {
    const result = await resolveAmbiguousName(identifier);
    if (result.kind === "ambiguous") {
      return outputErrorAndExit(
        json,
        `Multiple coins match "${identifier}" (a creator coin and a trend coin).`,
        "Pass the coin address to choose which one to edit.",
      );
    }
    if (result.kind !== "found") {
      return outputErrorAndExit(
        json,
        result.message ?? `No coin found matching "${identifier}".`,
        "Pass a coin address, or a creator/trend name.",
      );
    }
    address = result.coin.address;
  }

  const response = await getCoin({ address });
  const token = response.data?.zora20Token;
  if (!token) {
    return outputErrorAndExit(
      json,
      `No coin found at ${address}.`,
      "Pass a coin address you created, or a creator/trend name.",
    );
  }

  if (!token.tokenUri) {
    return outputErrorAndExit(
      json,
      `Coin ${token.address} has no metadata URI, so it can't be edited.`,
    );
  }

  return {
    address: token.address,
    name: token.name ?? token.address,
    symbol: token.symbol ?? "",
    tokenUri: token.tokenUri,
    creatorAddress: token.creatorAddress ?? undefined,
  };
}

/**
 * `zora coin edit` — edit a post's image and/or description (caption) while
 * keeping its name/ticker fixed.
 *
 * Mirrors the Zora app's "Edit post": fetch the coin's current metadata, apply
 * the changes, re-upload the metadata to IPFS, and point the coin's
 * `contractURI` at the new metadata on-chain. The title/ticker can't be edited
 * (the app keeps it fixed for coins too). Only the coin's creator can edit it.
 */
async function runEdit(
  command: Command,
  identifierArg: string | undefined,
  opts: EditOptions,
): Promise<void> {
  const json = getJson(command);

  const identifier = (identifierArg ?? "").trim();
  if (!identifier) {
    return outputErrorAndExit(
      json,
      "Missing coin to edit.",
      "Usage: zora coin edit <address | name> [--image <path>] [--description <text>]",
    );
  }

  // Both fetching the current metadata and uploading the new metadata require
  // an API key (same as `coin create`).
  const apiKey = getApiKey();
  if (!apiKey) {
    return outputErrorAndExit(
      json,
      "An API key is required to edit a coin.",
      "Run 'zora auth configure' to set your API key.",
    );
  }
  setApiKey(apiKey);

  // Editing is an owner-only on-chain action, so a wallet is required. This is
  // only a fail-fast presence check (mirrors `coin create`): `resolveAccounts()`
  // below does the actual key loading, so `key` itself is intentionally unused.
  const key = process.env.ZORA_PRIVATE_KEY || getPrivateKey();
  if (!key) {
    return outputErrorAndExit(
      json,
      "No wallet configured.",
      "Run 'zora agent create' to set up your Zora agent.",
    );
  }

  // Decide what's changing and validate the image locally *before* any network
  // call, so the no-op cases fail fast without a wasted `getCoin` round-trip. An
  // image change is opt-in (`--image`); with neither flag in --json mode there's
  // nothing to edit (the interactive prompt is handled after we have the coin).
  const wantsImage = opts.image !== undefined;
  let descriptionEdit = opts.description;
  if (descriptionEdit === undefined && !wantsImage && json) {
    return outputErrorAndExit(
      json,
      "Nothing to edit.",
      "Pass --image and/or --description.",
    );
  }

  // Validate the new image file (existence + supported type) before any work.
  let imageMime: string | undefined;
  if (wantsImage) {
    const imagePath = opts.image!;
    if (!existsSync(imagePath)) {
      return outputErrorAndExit(
        json,
        `Image file not found: ${imagePath}`,
        "Provide a path to an existing local image file.",
      );
    }
    const mime = imageMimeForPath(imagePath);
    if (!mime) {
      return outputErrorAndExit(
        json,
        `Unsupported image type: ${extname(imagePath).toLowerCase() || "(no extension)"}`,
        "Supported types: PNG, JPEG, JPG, GIF, SVG.",
      );
    }
    imageMime = mime;
  }

  const target = await resolveEditTarget(json, identifier);

  // Prefer the smart wallet path when one is configured, otherwise use the EOA
  // — identical to `coin create`, so the edit signs with the creating wallet.
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

  // `setContractURI` is owner-only. The creator is the owner for coins created
  // through Zora, so fail fast on a mismatch rather than after a reverted tx.
  // When the indexer doesn't report a creator (older coins or indexing gaps) we
  // can't verify ownership client-side, so warn and let the chain enforce it
  // rather than silently proceeding to a tx that may revert.
  if (!target.creatorAddress) {
    if (!json) {
      console.error(
        "\x1b[33mWarning:\x1b[0m couldn't verify this coin's creator — the transaction will revert (and waste gas) if you're not the owner.",
      );
    }
  } else if (target.creatorAddress.toLowerCase() !== creator.toLowerCase()) {
    return outputErrorAndExit(
      json,
      "You can only edit a coin you created.",
      `${target.name} was created by ${target.creatorAddress}, but your wallet is ${creator}.`,
    );
  }

  const walletType = usingSmartWallet ? "smart_wallet" : "eoa";

  // Read as a getter so the edited flags reflect the final `descriptionEdit`,
  // whether it came from `--description` or the interactive prompt below.
  const baseProps = () => ({
    coin: target.address,
    edited_image: wantsImage,
    edited_description: descriptionEdit !== undefined,
    wallet_type: walletType,
    output_format: json ? "json" : "static",
  });

  const fail = async (
    stage: string,
    err: unknown,
    message: string,
    suggestion?: string,
  ): Promise<never> => {
    track("cli_edit", {
      ...baseProps(),
      success: false,
      stage,
      error_type: err instanceof Error ? err.constructor.name : "unknown",
      error_message: err instanceof Error ? err.message : String(err),
      error: serializeError(err),
    });
    await shutdownAnalytics();
    return outputErrorAndExit(json, message, suggestion);
  };

  const uploader = createZoraUploaderForCreator(creator);

  // Read the coin's current on-chain metadata up front: it's the single source
  // of truth for both the interactive caption default and the merge base. The
  // indexer's `description` (from getCoin) can lag IPFS, so seeding the prompt
  // from it could pre-fill — and then persist — a stale caption the user keeps.
  let previousMetadata: CoinMetadata;
  try {
    previousMetadata = await fetchCoinMetadata(target.tokenUri);
  } catch (err) {
    return fail(
      "fetch",
      err,
      `Failed to read the coin's current metadata: ${formatError(err)}`,
    );
  }

  // With neither flag in interactive mode, prompt for a new caption pre-filled
  // with the current one (the --json no-op case was already rejected above).
  if (descriptionEdit === undefined && !wantsImage) {
    descriptionEdit = await input({
      message: "New description (caption):",
      default:
        typeof previousMetadata.description === "string"
          ? previousMetadata.description
          : "",
    });
  }

  if (!opts.yes && !json) {
    console.log(`\n Edit coin\n`);
    console.log(`   Coin         ${target.name} (${target.symbol})`);
    console.log(`   Address      ${target.address}`);
    if (wantsImage) {
      console.log(`   New image    ${opts.image}`);
    }
    if (descriptionEdit !== undefined) {
      console.log(`   Description  ${descriptionEdit || "(cleared)"}`);
    }
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

  // Upload the new image (if any) and the merged metadata.
  let newTokenUri: string;
  try {
    let imageUri: string | undefined;
    if (wantsImage) {
      const imageFile = new File(
        [readFileSync(opts.image!)],
        basename(opts.image!),
        { type: imageMime! },
      );
      imageUri = (await uploader.upload(imageFile)).url;
    }

    const metadata = mergeMetadata(previousMetadata, {
      description: descriptionEdit,
      imageUri,
    });

    const metadataFile = new File([JSON.stringify(metadata)], "metadata.json", {
      type: "application/json",
    });
    newTokenUri = (await uploader.upload(metadataFile)).url;
  } catch (err) {
    return fail(
      "upload",
      err,
      `Failed to prepare updated metadata: ${formatError(err)}`,
    );
  }

  // Point the coin's contractURI at the new metadata on-chain.
  let txHash: string | null;
  try {
    const result = usingSmartWallet
      ? await updateCoinURISmartWallet(
          { coin: target.address as Address, newURI: newTokenUri },
          bundlerClient!,
          publicClient,
        )
      : await updateCoinURI(
          { coin: target.address as Address, newURI: newTokenUri },
          walletClient,
          publicClient,
          privateKeyAccount,
        );
    txHash = result.hash ?? null;
  } catch (err) {
    return fail(
      "update",
      err,
      `Failed to edit coin: ${formatError(err)}`,
      gasErrorSuggestion(err, smartWalletAccount ?? privateKeyAccount),
    );
  }

  const edited: string[] = [];
  if (wantsImage) edited.push("image");
  if (descriptionEdit !== undefined) edited.push("description");

  track("cli_edit", {
    ...baseProps(),
    success: true,
    tx_hash: txHash,
  });

  outputData(json, {
    json: {
      action: "edit",
      coin: target.address,
      name: target.name,
      symbol: target.symbol,
      edited,
      tokenUri: newTokenUri,
      tx: txHash,
      walletType,
    },
    render: () => {
      console.log(`\n Edited ${target.name} (${target.symbol})\n`);
      console.log(`   Address      ${target.address}`);
      console.log(`   Updated      ${edited.join(", ")}`);
      console.log(`   Tx           ${txHash ?? "unknown"}\n`);
    },
  });
}

export const coinEditCommand = new Command("edit")
  .description("Edit a post's image and/or description (not the name/ticker)")
  .argument("[identifier]", "Coin address, or a creator/trend name")
  .option("--description <description>", "New description (caption)")
  .option("--image <path>", "Path to a new local image file to upload")
  .option("--yes", "Skip confirmation and edit directly")
  .action(async function (
    this: Command,
    identifier: string | undefined,
    opts: EditOptions,
  ) {
    await runEdit(this, identifier, opts);
  });
