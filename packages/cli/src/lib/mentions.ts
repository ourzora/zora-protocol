import { getProfile } from "@zoralabs/coins-sdk";

/**
 * Zora encodes an @mention inside comment text as a markdown link whose label is
 * the handle and whose target is the mentioned account's Zora profile URL keyed
 * by wallet address:
 *
 *   [@handle](https://zora.co/@0x1234...abcd)
 *
 * The wallet address in the URL — not the handle label — is what the backend
 * resolves to an account and what drives mention notifications; the label is
 * cosmetic (the backend refreshes it to the current username on read). A
 * handle-only URL renders as a link on web but does NOT trigger a mention, so
 * the CLI must resolve each `@handle` to an address before submitting.
 *
 * This mirrors the web/mobile mention encoder (`inputUtils.ts` `insertMention`)
 * and the backend's address-only URL rule (`utils/mentions.py`).
 */

const ZORA_PROFILE_URL_BASE = "https://zora.co/@";

/**
 * Matches a bare `@handle` typed in free text — the leading group keeps the
 * preceding start-of-string/whitespace so the replacement can re-emit it, and
 * requiring that boundary avoids matching email-like `foo@bar` or the `@` inside
 * an already-encoded `[@handle](url)` token (preceded by `[`) or its URL
 * (preceded by `/`). Handle charset matches Zora usernames (alphanumeric + `_`).
 */
const RAW_HANDLE_PATTERN = "(^|\\s)@([a-zA-Z0-9_]{1,30})";

/** Encoded-mention token matcher, used to render tokens back to plain `@handle`. */
const MENTION_TOKEN_PATTERN = "\\[@([^\\]]+)\\]\\([^)]*\\)";

export interface ResolvedMention {
  /** The handle as typed (without the leading `@`). */
  handle: string;
  /** The wallet address the mention resolved to. */
  address: string;
}

export interface MentionResolution {
  /** The comment text with resolved `@handle`s replaced by markdown-link tokens. */
  text: string;
  /** The mentions that resolved and were encoded. */
  resolved: ResolvedMention[];
  /** Handles that could not be resolved and were left as raw `@handle` text. */
  skipped: string[];
}

/** Build a mention token for a resolved handle + address. */
export function formatMention(handle: string, address: string): string {
  return `[@${handle}](${ZORA_PROFILE_URL_BASE}${address.toLowerCase()})`;
}

/**
 * Render encoded mention tokens back to plain `@handle` for human-readable
 * output (the stored/returned text contains the full markdown-link tokens).
 */
export function toPlainMentions(text: string): string {
  return text.replace(new RegExp(MENTION_TOKEN_PATTERN, "g"), "@$1");
}

/**
 * Resolve a handle to the wallet address a mention should point at, matching the
 * web precedence (smart wallet → external wallet → public wallet). Returns null
 * when the handle has no Zora profile or no usable wallet address, so the caller
 * can leave the raw `@handle` untouched.
 */
export async function resolveHandleToAddress(
  handle: string,
): Promise<string | null> {
  const response = await getProfile({ identifier: handle });
  const profile = response?.data?.profile;
  if (!profile) return null;

  const linked = profile.linkedWallets?.edges?.map((e) => e.node) ?? [];
  const smart = linked.find(
    (w) => w.walletType === "SMART_WALLET",
  )?.walletAddress;
  const external = linked.find(
    (w) => w.walletType === "EXTERNAL",
  )?.walletAddress;
  return smart ?? external ?? profile.publicWallet?.walletAddress ?? null;
}

/**
 * Encode the `@handle` mentions in a comment. Each distinct handle is resolved
 * once (via the injected `resolver`, defaulting to {@link resolveHandleToAddress});
 * resolved handles are rewritten to `[@handle](url)` tokens, and anything that
 * fails to resolve — an unknown handle, a resolver error, or a network blip — is
 * left exactly as typed so a stray `@` never blocks posting.
 */
export async function resolveMentions(
  text: string,
  resolver: (handle: string) => Promise<string | null> = resolveHandleToAddress,
): Promise<MentionResolution> {
  const matches = [...text.matchAll(new RegExp(RAW_HANDLE_PATTERN, "g"))];
  if (matches.length === 0) return { text, resolved: [], skipped: [] };

  // Resolve each distinct handle once (case-insensitive), in parallel. A failed
  // lookup maps to null → the handle is skipped rather than throwing.
  const uniqueHandles = [...new Set(matches.map((m) => m[2].toLowerCase()))];
  const addressByHandle = new Map<string, string | null>();
  await Promise.all(
    uniqueHandles.map(async (handle) => {
      try {
        addressByHandle.set(handle, await resolver(handle));
      } catch {
        addressByHandle.set(handle, null);
      }
    }),
  );

  const resolved: ResolvedMention[] = [];
  const skipped: string[] = [];
  const out = text.replace(
    new RegExp(RAW_HANDLE_PATTERN, "g"),
    (_full, lead: string, handle: string) => {
      const address = addressByHandle.get(handle.toLowerCase());
      if (address) {
        if (!resolved.some((r) => r.handle === handle)) {
          resolved.push({ handle, address });
        }
        return `${lead}${formatMention(handle, address)}`;
      }
      if (!skipped.includes(handle)) skipped.push(handle);
      return `${lead}@${handle}`;
    },
  );

  return { text: out, resolved, skipped };
}
