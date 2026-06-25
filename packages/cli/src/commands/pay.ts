import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import confirm from "@inquirer/confirm";
import input from "@inquirer/input";
import { Command } from "commander";
import {
  erc20Abi,
  formatUnits,
  getAddress,
  isAddress,
  type Address,
} from "viem";
import type { PaymentRequired, PaymentRequirements } from "@x402/core/types";
import { decodePaymentResponseHeader, wrapFetchWithPayment } from "@x402/fetch";
import { shutdownAnalytics, track } from "../lib/analytics.js";
import { serializeError } from "../lib/errors.js";
import { safeExit, SUCCESS } from "../lib/exit.js";
import { formatAmountDisplay } from "../lib/format.js";
import { getJson, outputErrorAndExit, outputJson } from "../lib/output.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";
import {
  BASE_NETWORK,
  createX402Client,
  parseAcceptsInput,
  PAYMENT_RESPONSE_HEADER,
  PAYMENT_SIGNATURE_HEADER,
  resolvePayment,
  signPayment,
} from "../lib/x402/index.js";
import { type ReadOnlyClient, selectForFetch } from "../lib/x402/select.js";
import { resolveX402Signer } from "../lib/x402/signer.js";

type PayOptions = {
  accepts?: string;
  url?: string;
  method?: string;
  data?: string;
  asset?: string;
  maxValue?: string;
  eoa?: boolean;
  yes?: boolean;
  output?: string;
};

/** Best-effort ERC-20 metadata for display; never throws. */
async function readAssetMeta(
  publicClient: ReadOnlyClient,
  asset: Address,
): Promise<{ decimals: number; symbol: string }> {
  try {
    const [decimals, symbol] = await Promise.all([
      publicClient.readContract({
        abi: erc20Abi,
        address: asset,
        functionName: "decimals",
      }),
      publicClient.readContract({
        abi: erc20Abi,
        address: asset,
        functionName: "symbol",
      }),
    ]);
    return { decimals, symbol };
  } catch {
    return { decimals: 0, symbol: "" };
  }
}

function printPaymentPreview(info: {
  resource: string;
  description: string;
  payTo: string;
  amountFormatted: string;
  symbol: string;
  walletType: string;
}): void {
  console.log(`\n Pay for x402 resource\n`);
  if (info.resource) console.log(`   Resource     ${info.resource}`);
  if (info.description) console.log(`   Description  ${info.description}`);
  console.log(
    `   Amount       ${info.amountFormatted}${info.symbol ? ` ${info.symbol}` : ""}`,
  );
  console.log(`   Pay to       ${info.payTo}`);
  console.log(`   Paying from  ${info.walletType}`);
  console.log("");
}

/** Builder mode: sign an `accepts` array into a PAYMENT-SIGNATURE header. No HTTP. */
async function runBuildMode(opts: PayOptions, json: boolean): Promise<void> {
  let paymentRequired: PaymentRequired;
  try {
    paymentRequired = parseAcceptsInput(opts.accepts!);
  } catch (err) {
    return outputErrorAndExit(
      json,
      err instanceof Error ? err.message : String(err),
    );
  }

  const { privateKeyAccount, smartWalletAccount } = await resolveAccounts();
  const { publicClient } = createClients(privateKeyAccount, smartWalletAccount);
  const signer = resolveX402Signer(
    privateKeyAccount,
    smartWalletAccount,
    opts.eoa,
  );

  const preferredAsset = opts.asset
    ? validateAssetOption(opts.asset, json)
    : undefined;
  const maxValue = parseMaxValue(opts.maxValue, json);

  // Select first (balance + cap only — no signing yet) so the user can decline
  // before any redeemable authorization is created.
  const result = await resolvePayment({
    paymentRequired,
    publicClient,
    address: signer.address,
    preferredAsset,
    maxValue,
  });

  if (result.kind === "none") {
    track("cli_pay", {
      mode: "build",
      wallet_type: signer.walletType,
      output_format: json ? "json" : "static",
      success: false,
      reason: result.reason,
    });
    return outputErrorAndExit(
      json,
      result.reason,
      "Fund the wallet on Base or pass --asset to choose a held token.",
    );
  }

  const { requirement } = result;
  const asset = getAddress(requirement.asset);
  const meta = await readAssetMeta(publicClient, asset);
  const amountFormatted = meta.decimals
    ? formatAmountDisplay(BigInt(requirement.amount), meta.decimals)
    : requirement.amount;
  const resource = paymentRequired.resource;

  if (!opts.yes && !json) {
    printPaymentPreview({
      resource: resource?.url ?? "",
      description: resource?.description ?? "",
      payTo: requirement.payTo,
      amountFormatted,
      symbol: meta.symbol,
      walletType: signer.walletType,
    });
    const ok = await confirm({
      message: "Authorize this payment?",
      default: false,
    });
    if (!ok) {
      console.error("Aborted.");
      return safeExit(SUCCESS);
    }
  }

  // Only now produce the signed authorization.
  const { header } = await signPayment({
    paymentRequired,
    requirement,
    signer,
  });

  track("cli_pay", {
    mode: "build",
    network: BASE_NETWORK,
    asset,
    amount_atomic: requirement.amount,
    wallet_type: signer.walletType,
    output_format: json ? "json" : "static",
    success: true,
  });

  if (json) {
    outputJson({
      action: "pay",
      mode: "build",
      headerName: PAYMENT_SIGNATURE_HEADER,
      header,
      requirement: {
        scheme: requirement.scheme,
        network: requirement.network,
        asset,
        payTo: requirement.payTo,
        amount: requirement.amount,
        amountFormatted: meta.decimals
          ? formatUnits(BigInt(requirement.amount), meta.decimals)
          : null,
        symbol: meta.symbol || null,
        resource: resource?.url || null,
        description: resource?.description || null,
      },
      payerWallet: signer.walletType,
    });
    return;
  }

  console.log(`\n Signed x402 payment\n`);
  console.log(
    `   Amount       ${amountFormatted}${meta.symbol ? ` ${meta.symbol}` : ""}`,
  );
  console.log(`   Pay to       ${requirement.payTo}`);
  console.log(`   Paying from  ${signer.walletType}\n`);
  console.log(`   Attach this header to the retry request:\n`);
  console.log(`   ${PAYMENT_SIGNATURE_HEADER}: ${header}\n`);
}

/** Round-trip mode: fetch a URL, paying any x402 challenge automatically. */
async function runFetchMode(opts: PayOptions, json: boolean): Promise<void> {
  const { privateKeyAccount, smartWalletAccount } = await resolveAccounts();
  const signer = resolveX402Signer(
    privateKeyAccount,
    smartWalletAccount,
    opts.eoa,
  );

  const preferredAsset = opts.asset
    ? validateAssetOption(opts.asset, json)
    : undefined;
  const maxValue = parseMaxValue(opts.maxValue, json);

  // x402 calls this selector with the response's accepts array (sync). It
  // restricts to Base `exact`, honors an asset preference, and enforces the
  // spend cap (throwing if exceeded) — see selectForFetch.
  const selector = (_x402Version: number, accepts: PaymentRequirements[]) =>
    selectForFetch(accepts, { preferredAsset, maxValue });

  const client = createX402Client(signer, selector);
  const fetchWithPay = wrapFetchWithPayment(fetch, client);

  let response: Response;
  try {
    response = await fetchWithPay(opts.url!, {
      method: opts.method ?? "GET",
      ...(opts.data !== undefined
        ? {
            body: opts.data,
            headers: { "Content-Type": "application/json" },
          }
        : {}),
    });
  } catch (err) {
    track("cli_pay", {
      mode: "fetch",
      wallet_type: signer.walletType,
      output_format: json ? "json" : "static",
      success: false,
      error_type: err instanceof Error ? err.constructor.name : "unknown",
      error: serializeError(err),
    });
    await shutdownAnalytics();
    return outputErrorAndExit(
      json,
      `x402 request failed: ${err instanceof Error ? err.message : String(err)}`,
      "Check the URL, ensure the wallet holds enough USDC on Base, and consider raising --max-value.",
    );
  }

  // Read the body once as raw bytes so we can serve text and binary alike.
  const contentType = response.headers.get("content-type") ?? "";
  const bytes = Buffer.from(await response.arrayBuffer());
  const isText = isTextContentType(contentType);

  const settlementHeader =
    response.headers.get(PAYMENT_RESPONSE_HEADER) ??
    response.headers.get("x-payment-response");
  let settlement: ReturnType<typeof decodePaymentResponseHeader> | null = null;
  if (settlementHeader) {
    try {
      settlement = decodePaymentResponseHeader(settlementHeader);
    } catch {
      settlement = null;
    }
  }

  // Persist the raw resource to disk when requested (works for any content type).
  let savedTo: string | undefined;
  if (opts.output) {
    try {
      writeFileSync(opts.output, bytes);
      savedTo = opts.output;
    } catch (err) {
      return outputErrorAndExit(
        json,
        `Failed to write --output file: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
  }

  track("cli_pay", {
    mode: "fetch",
    network: BASE_NETWORK,
    wallet_type: signer.walletType,
    status: response.status,
    paid: settlement != null,
    content_type: contentType || null,
    binary: !isText,
    saved: savedTo != null,
    output_format: json ? "json" : "static",
    success: response.ok,
  });

  if (json) {
    const base = {
      action: "pay",
      mode: "fetch",
      url: opts.url,
      status: response.status,
      contentType: contentType || null,
      paid: settlement != null,
      settlement: settlement
        ? {
            success: settlement.success,
            transaction: settlement.transaction,
            network: settlement.network,
            payer: settlement.payer,
          }
        : null,
    };

    // The resource is already paid for, so always hand back something durable
    // and never require a re-run. When --output was given the body is already on
    // disk; otherwise persist it to a temp file. Text bodies are also inlined
    // (cheap and convenient); binary bodies are referenced by path only, so the
    // agent moves the file rather than round-tripping base64 through its context.
    const path = savedTo ?? writeTempResponse(bytes, opts.url, contentType);
    if (isText) {
      outputJson({
        ...base,
        encoding: "utf8",
        body: tryParseJson(bytes.toString("utf8")),
        savedTo: path,
        bytes: bytes.length,
      });
    } else {
      outputJson({
        ...base,
        encoding: "binary",
        savedTo: path,
        bytes: bytes.length,
      });
    }
    return;
  }

  console.log(`\n x402 request ${response.ok ? "succeeded" : "failed"}\n`);
  console.log(`   Status       ${response.status}`);
  if (contentType) console.log(`   Type         ${contentType}`);
  if (settlement) {
    console.log(`   Paid         yes (from ${signer.walletType})`);
    console.log(`   Tx           ${settlement.transaction}`);
  } else {
    console.log(`   Paid         no payment was required`);
  }

  if (savedTo) {
    console.log(`   Saved        ${savedTo} (${bytes.length} bytes)\n`);
    return;
  }

  if (isText) {
    console.log(`\n   Response:\n`);
    console.log(prettyIfJson(bytes.toString("utf8")));
    console.log("");
    return;
  }

  // Binary, and no --output was given. The resource is already paid for, so
  // never bail and force a re-run (a second payment): prompt for a destination,
  // or auto-save to a sensible default when non-interactive.
  const suggested = suggestedFilename(opts.url, contentType);
  const nonInteractive = !!opts.yes || !process.stdin.isTTY;
  let dest = suggested;
  if (nonInteractive) {
    console.log(`\n   Binary response (${bytes.length} bytes) — saving.`);
  } else {
    console.log(`\n   Binary response (${bytes.length} bytes).`);
    const answer = await input({
      message: "Save response to file:",
      default: suggested,
    });
    dest = answer.trim() || suggested;
  }
  try {
    writeFileSync(dest, bytes);
  } catch (err) {
    return outputErrorAndExit(
      false,
      `Failed to write file: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
  console.log(`   Saved        ${dest} (${bytes.length} bytes)\n`);
}

/**
 * Whether a response body should be treated as UTF-8 text (vs binary). Used to
 * decide between inlining/printing the body and referencing it by file path. A
 * missing content type defaults to text.
 */
function isTextContentType(contentType: string): boolean {
  const t = contentType.split(";")[0].trim().toLowerCase();
  if (t === "") return true;
  if (t.startsWith("text/")) return true;
  if (t.endsWith("+json") || t.endsWith("+xml")) return true;
  return [
    "application/json",
    "application/xml",
    "application/javascript",
    "application/x-www-form-urlencoded",
    "image/svg+xml",
  ].includes(t);
}

const CONTENT_TYPE_EXT: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/gif": "gif",
  "image/webp": "webp",
  "image/avif": "avif",
  "application/pdf": "pdf",
  "application/zip": "zip",
  "application/gzip": "gz",
  "audio/mpeg": "mp3",
  "audio/wav": "wav",
  "video/mp4": "mp4",
  "application/octet-stream": "bin",
  "text/plain": "txt",
  "text/markdown": "md",
};

/**
 * Suggest a filename for a response: a basename with an extension from the URL
 * path when available, otherwise `x402-response.<ext>` derived from the content
 * type (e.g. `png`, `pdf`, `json`, `txt`).
 */
function suggestedFilename(
  url: string | undefined,
  contentType: string,
): string {
  try {
    if (url) {
      const base = new URL(url).pathname.split("/").filter(Boolean).pop();
      if (base && /\.[a-z0-9]{1,8}$/i.test(base)) return base;
    }
  } catch {
    // malformed URL — fall through to a content-type-derived name
  }
  const ct = contentType.split(";")[0].trim().toLowerCase();
  const subtype = ct.split("/")[1] ?? "";
  const ext =
    CONTENT_TYPE_EXT[ct] ?? (/^[a-z0-9]{1,8}$/.test(subtype) ? subtype : "bin");
  return `x402-response.${ext}`;
}

/**
 * Persist an already-paid response body to a fresh temp file and return its
 * path. Lets the agent read text or move binary from disk without re-running
 * the (paid) request or round-tripping bytes through its context.
 */
function writeTempResponse(
  bytes: Buffer,
  url: string | undefined,
  contentType: string,
): string {
  const dir = mkdtempSync(join(tmpdir(), "zora-x402-"));
  const path = join(dir, suggestedFilename(url, contentType));
  writeFileSync(path, bytes);
  return path;
}

/** Pretty-print JSON text with 2-space indentation; return other text as-is. */
function prettyIfJson(text: string): string {
  try {
    return JSON.stringify(JSON.parse(text), null, 2);
  } catch {
    return text;
  }
}

function tryParseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function validateAssetOption(value: string, json: boolean): Address {
  if (!isAddress(value)) {
    return outputErrorAndExit(json, `--asset must be a 0x address: ${value}`);
  }
  return getAddress(value);
}

function parseMaxValue(
  value: string | undefined,
  json: boolean,
): bigint | undefined {
  if (value === undefined) return undefined;
  try {
    const parsed = BigInt(value);
    if (parsed <= 0n) throw new Error("must be positive");
    return parsed;
  } catch {
    return outputErrorAndExit(
      json,
      "--max-value must be a positive integer in the asset's atomic units (e.g. 1000000 = 1 USDC).",
    );
  }
}

export const payCommand = new Command("pay")
  .description("Pay for an x402-protected resource on Base")
  .option(
    "--accepts <json>",
    "x402 'accepts' array, 402 response body, or base64 PAYMENT-REQUIRED header (inline JSON, @file, or - for stdin). Signs and outputs the PAYMENT-SIGNATURE header.",
  )
  .option(
    "--url <url>",
    "Fetch a URL, automatically paying any x402 402 challenge and returning the resource.",
  )
  .option("--method <method>", "HTTP method for --url mode", "GET")
  .option("--data <body>", "Request body (JSON) for --url mode")
  .option("--asset <address>", "Prefer paying with this ERC-20 asset (0x...)")
  .option(
    "--max-value <atomic>",
    "Maximum payment in the asset's atomic units; refuse to pay above it",
  )
  .option("--eoa", "Pay from the EOA instead of the smart wallet")
  .option(
    "--output <file>",
    "Write the response body to a file (raw bytes; works for binary resources)",
  )
  .option("--yes", "Skip confirmation")
  .action(async function (this: Command, opts: PayOptions) {
    const json = getJson(this);

    if (!opts.accepts && !opts.url) {
      return outputErrorAndExit(
        json,
        "Provide --accepts <json> to sign a payment, or --url <url> to pay-and-fetch.",
        "Usage: zora pay --accepts '<402 accepts JSON>'  |  zora pay --url <url>",
      );
    }
    if (opts.accepts && opts.url) {
      return outputErrorAndExit(
        json,
        "--accepts and --url cannot be used together.",
        "Use --accepts to only sign a payment, or --url to pay and fetch.",
      );
    }

    if (opts.accepts) {
      await runBuildMode(opts, json);
    } else {
      await runFetchMode(opts, json);
    }
  });
