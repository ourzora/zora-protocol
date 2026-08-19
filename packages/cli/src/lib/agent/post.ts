import { Buffer } from "node:buffer";
import { getAddress, type Address, type Hex, type LocalAccount } from "viem";
import {
  BASE_CHAIN_ID,
  ipfsUpload,
  trpcRequest,
  type ChainClient,
} from "./zora-client.js";
import { renderFirstPostCard } from "./render-card.js";
import type { RawUserOperation } from "./user-op.js";
import { signSimulateSubmit, type FinalizeResult } from "./submit.js";
import { TICKER_MIN_LENGTH, validateTicker } from "../ticker.js";

export interface FirstPostResult extends FinalizeResult {
  /** The caption rendered on the card; also the coin name when no title is given. */
  caption: string;
  ticker: string;
  imageUri: string;
  contractUri: string;
  /**
   * The deployed content-coin address, when minted. Resolved from the inline
   * `submitUserOperation` logs when present, otherwise from the mined
   * transaction's receipt (see {@link resolveCoinAddress}). Still best-effort:
   * absent only if both sources are unavailable.
   */
  coinAddress?: Address;
}

/** How many times to poll for the transaction receipt before giving up. */
const DEFAULT_RECEIPT_ATTEMPTS = 5;
/** Delay between receipt polls. */
const RECEIPT_POLL_MS = 2000;

const NAME_ABI = [
  {
    type: "function",
    name: "name",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
] as const;

/**
 * Find the deployed coin among a set of logs by matching its on-chain name.
 *
 * Makes up to one `readContract` (`name()`) call per unique log address, and
 * returns undefined if none matches (the logs are empty, the shape is
 * unexpected, or the names differ).
 */
async function findDeployedCoin(
  client: ChainClient,
  logs: unknown[],
  expectedName: string,
): Promise<Address | undefined> {
  const seen = new Set<string>();
  for (const log of logs) {
    const address = (log as { address?: string })?.address;
    if (!address || seen.has(address.toLowerCase())) continue;
    seen.add(address.toLowerCase());
    try {
      const name = await client.readContract({
        address: getAddress(address),
        abi: NAME_ABI,
        functionName: "name",
      });
      if (name === expectedName) return getAddress(address);
    } catch {
      // not a coin / no name() — skip
    }
  }
  return undefined;
}

/**
 * Resolve the deployed content-coin address for a submitted first post.
 *
 * Two sources, in order:
 *   1. The inline logs returned by `submitUserOperation` (no extra RPC).
 *   2. The mined transaction's receipt logs, fetched by hash — the authoritative
 *      source. The inline logs are frequently empty (notably under CI/headless
 *      runs), which previously left every post without a link; the receipt is
 *      always populated once the sponsored tx confirms, so we poll for it.
 *
 * Still best-effort: any RPC hiccup just leaves the address unresolved (the post
 * itself already succeeded), so the caller can fall back to a profile link
 * rather than failing.
 */
async function resolveCoinAddress(
  client: ChainClient,
  submitted: { hash: string; logs?: unknown[] },
  expectedName: string,
  opts: {
    receiptAttempts?: number;
    sleep?: (ms: number) => Promise<void>;
  } = {},
): Promise<Address | undefined> {
  // 1. Fast path — inline submit logs, when the backend returned them.
  const fromInline = await findDeployedCoin(
    client,
    submitted.logs ?? [],
    expectedName,
  );
  if (fromInline) return fromInline;

  // 2. Receipt fallback — fetch the mined transaction's authoritative logs.
  if (!client.getTransactionReceipt || !submitted.hash) return undefined;
  const attempts = opts.receiptAttempts ?? DEFAULT_RECEIPT_ATTEMPTS;
  const sleep =
    opts.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const receipt = await client.getTransactionReceipt({
        hash: submitted.hash as Hex,
      });
      // A fetched receipt is final — its logs won't change — so scan it once
      // and return whatever we find (the matched address, or undefined). The
      // retry budget is reserved for the fetch itself failing below; re-polling
      // a receipt we already have would only re-read identical logs.
      const logs = Array.isArray(receipt?.logs) ? receipt.logs : [];
      return await findDeployedCoin(client, logs, expectedName);
    } catch {
      // Receipt not yet available (the tx is still confirming) or a transient
      // RPC error — this is the only case worth retrying.
    }
    if (attempt < attempts - 1) await sleep(RECEIPT_POLL_MS);
  }
  return undefined;
}

/**
 * Derive a coin ticker from a caption/title: uppercase alphanumerics only,
 * capped at 10 characters, with a sensible fallback when too little usable text
 * remains (an emoji-only caption, or a single character below the 2-char
 * minimum). The result is always a valid ticker.
 */
export function deriveTicker(text: string): string {
  const cleaned = text
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 10);
  return cleaned.length >= TICKER_MIN_LENGTH ? cleaned : "POST";
}

/**
 * Publish the agent's first post — a Zora content coin whose media is a meme card
 * rendered from the brand template: the caller's photo (`image`) as the full-bleed
 * background, `caption` as the big centered text, and `handle` as the faint footer.
 * The card PNG + metadata are uploaded to IPFS, then the (sponsored) content-coin
 * UserOp is built, signed, and submitted exactly like the creator coin. `title`
 * and `description` set the coin metadata (defaulting to the caption); with
 * `dryRun`, the card + metadata are uploaded but nothing is minted.
 */
export async function createFirstPost(params: {
  token: string;
  account: LocalAccount;
  client: ChainClient;
  smartWallet: Address;
  owners: Address[];
  dryRun: boolean;
  /** The big centered meme caption (required). */
  caption: string;
  /** The background photo (required): raw bytes + MIME type. */
  image: { bytes: Uint8Array; mimeType: string };
  /** The faint footer handle, e.g. "zora.co/alice". */
  handle: string;
  /**
   * Coin ticker (symbol). When omitted, it's derived from the title. When
   * provided, it's validated (2–20 alphanumeric chars) and used as-is; an
   * invalid value throws.
   */
  ticker?: string;
  /** Coin name; defaults to the caption when omitted. */
  title?: string;
  /** Coin description; defaults to the caption when omitted. */
  description?: string;
  /** Max attempts to poll for the tx receipt when resolving the coin address. */
  receiptAttempts?: number;
  sleep?: (ms: number) => Promise<void>;
}): Promise<FirstPostResult> {
  const { token, account, client, smartWallet, owners, dryRun } = params;
  const { caption, image, handle } = params;
  const name = params.title?.trim() || caption;
  const description = params.description?.trim() || caption;
  // A caller-supplied ticker is forced (validated and used verbatim); otherwise
  // derive one from the title. Validation throws here so an invalid ticker
  // surfaces as a post error rather than a rejected coin downstream — though the
  // command layer validates first, so it normally fails fast before this point.
  const customTicker = params.ticker?.trim();
  if (customTicker) {
    const tickerError = validateTicker(customTicker);
    if (tickerError) throw new Error(tickerError);
  }
  const ticker = customTicker || deriveTicker(name);

  const png = await renderFirstPostCard({
    image: image.bytes,
    mimeType: image.mimeType,
    caption,
    handle,
  });

  const imageUri = await ipfsUpload(token, "first-post.png", png, "image/png");
  const metadata = {
    name,
    description,
    symbol: ticker,
    image: imageUri,
    content: { uri: imageUri, mime: "image/png" },
  };
  const contractUri = await ipfsUpload(
    token,
    "metadata.json",
    Buffer.from(JSON.stringify(metadata)),
    "application/json",
  );

  const { data, error } = await trpcRequest(
    token,
    "create.createCreateERC20UserOperationV2",
    {
      json: {
        chainId: BASE_CHAIN_ID,
        ownerAddress: smartWallet.toLowerCase(),
        // NOTE: `adminAddressess` is misspelled ON PURPOSE. The Zora BFF's zod
        // schema for this mutation keys on that exact (mis)spelling and rejects
        // the request ("expected array, received undefined") if it's renamed to
        // the correct `adminAddresses`. Verified against the live endpoint — do
        // not "fix" the spelling.
        adminAddressess: [...owners, smartWallet],
        name,
        ticker,
        contractURI: contractUri,
        value: "0",
        customPairCurrencyAddress: null,
        disableGasSponsorship: false,
      },
      meta: { values: { value: ["bigint"] } },
    },
  );
  if (!data) {
    throw new Error(
      `createCreateERC20UserOperationV2 failed: ${error ?? "no UserOp returned"}`,
    );
  }

  const finalize = await signSimulateSubmit({
    token,
    account,
    client,
    raw: data as RawUserOperation,
    dryRun,
  });
  const coinAddress = finalize.submitted
    ? await resolveCoinAddress(client, finalize.submitted, name, {
        receiptAttempts: params.receiptAttempts,
        sleep: params.sleep,
      })
    : undefined;
  return {
    ...finalize,
    caption,
    ticker,
    imageUri,
    contractUri,
    coinAddress,
  };
}
