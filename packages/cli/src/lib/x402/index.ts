import { readFileSync } from "node:fs";
import type { Address } from "viem";
import { type SelectPaymentRequirements, x402Client } from "@x402/core/client";
import {
  decodePaymentRequiredHeader,
  encodePaymentSignatureHeader,
} from "@x402/core/http";
import type {
  PaymentPayload,
  PaymentRequired,
  PaymentRequirements,
} from "@x402/core/types";
import { ExactEvmScheme } from "@x402/evm";
import {
  BASE_NETWORK,
  type ReadOnlyClient,
  selectPayableRequirement,
} from "./select.js";
import type { ResolvedX402Signer } from "./signer.js";

/** The x402 protocol version this CLI speaks. */
export const X402_VERSION = 2;

/** HTTP header carrying the signed payment proof on the retry request. */
export const PAYMENT_SIGNATURE_HEADER = "PAYMENT-SIGNATURE";
/** HTTP header carrying the settlement result on a successful response. */
export const PAYMENT_RESPONSE_HEADER = "PAYMENT-RESPONSE";

/**
 * Build an x402 v2 client that pays the `exact` scheme on Base with the given
 * signer. Shared by the builder and the round-trip fetch path.
 */
export const createX402Client = (
  signer: ResolvedX402Signer,
  selector?: SelectPaymentRequirements,
): x402Client =>
  new x402Client(selector).register(
    BASE_NETWORK,
    new ExactEvmScheme(signer.signer),
  );

/**
 * Parse the `--accepts` input into an x402 v2 `PaymentRequired`.
 *
 * Accepts the raw 402 response body (`{ x402Version, accepts, resource }`), a
 * bare `accepts` array, or a base64 `PAYMENT-REQUIRED` header value. The value
 * may be inline JSON, `@<path>` to read a file, or `-` to read stdin — mirroring
 * how agents pipe data into the CLI.
 */
export const parseAcceptsInput = (raw: string): PaymentRequired => {
  let text = raw.trim();

  if (text === "-") {
    // Reading fd 0 blocks forever on a TTY with nothing piped in — fail fast.
    if (process.stdin.isTTY) {
      throw new Error(
        "--accepts - expects the 402 challenge piped on stdin (none detected). Pipe it in, or pass it inline or via @file.",
      );
    }
    text = readFileSync(0, "utf-8").trim();
  } else if (text.startsWith("@")) {
    text = readFileSync(text.slice(1), "utf-8").trim();
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    // Not JSON — try decoding it as a base64 PAYMENT-REQUIRED header value.
    try {
      return decodePaymentRequiredHeader(text);
    } catch {
      throw new Error(
        "--accepts must be a 402 accepts array, a 402 response object, or a base64 PAYMENT-REQUIRED header value.",
      );
    }
  }

  if (Array.isArray(parsed)) {
    return {
      x402Version: X402_VERSION,
      resource: { url: "" },
      accepts: parsed as PaymentRequirements[],
    };
  }

  if (parsed && typeof parsed === "object" && "accepts" in parsed) {
    const obj = parsed as Partial<PaymentRequired>;
    if (!Array.isArray(obj.accepts)) {
      throw new Error("--accepts: the `accepts` field must be an array.");
    }
    return {
      x402Version:
        typeof obj.x402Version === "number" ? obj.x402Version : X402_VERSION,
      resource: obj.resource ?? { url: "" },
      accepts: obj.accepts,
      extensions: obj.extensions,
    };
  }

  throw new Error(
    "--accepts must be a 402 accepts array, a 402 response object, or a base64 PAYMENT-REQUIRED header value.",
  );
};

export type ResolvePaymentResult =
  | { kind: "selected"; requirement: PaymentRequirements; balance: bigint }
  | { kind: "none"; reason: string };

/**
 * Choose a payable entry from the `accepts` array — Base `exact`, an asset the
 * wallet holds, within the optional `maxValue` cap. **No signing happens here**,
 * so the result can be previewed and confirmed before any authorization exists.
 */
export const resolvePayment = async ({
  paymentRequired,
  publicClient,
  address,
  preferredAsset,
  maxValue,
}: {
  paymentRequired: PaymentRequired;
  publicClient: ReadOnlyClient;
  address: Address;
  preferredAsset?: Address;
  maxValue?: bigint;
}): Promise<ResolvePaymentResult> => {
  const selection = await selectPayableRequirement({
    accepts: paymentRequired.accepts,
    publicClient,
    walletAddress: address,
    preferredAsset,
  });

  if (selection.kind === "none") {
    return selection;
  }

  const required = BigInt(selection.requirement.amount);
  if (maxValue !== undefined && required > maxValue) {
    return {
      kind: "none",
      reason: `Payment of ${required} exceeds --max-value cap of ${maxValue} (atomic units of ${selection.requirement.asset}).`,
    };
  }

  return selection;
};

/**
 * Sign a chosen requirement into a base64 PAYMENT-SIGNATURE header. This is the
 * step that produces a redeemable EIP-3009 authorization, so call it only after
 * the user has confirmed (the `--yes`/`--json` paths confirm implicitly). It
 * performs no HTTP, so the same primitive also serves agent-to-agent payment
 * requests (e.g. an x402-schema payment encoded in an XMTP DM).
 */
export const signPayment = async ({
  paymentRequired,
  requirement,
  signer,
}: {
  paymentRequired: PaymentRequired;
  requirement: PaymentRequirements;
  signer: ResolvedX402Signer;
}): Promise<{ header: string; payload: PaymentPayload }> => {
  const client = createX402Client(signer);
  const payload = await client.createPaymentPayload({
    x402Version: paymentRequired.x402Version || X402_VERSION,
    resource: paymentRequired.resource,
    accepts: [requirement],
    extensions: paymentRequired.extensions,
  });
  return { header: encodePaymentSignatureHeader(payload), payload };
};

export { BASE_NETWORK };
