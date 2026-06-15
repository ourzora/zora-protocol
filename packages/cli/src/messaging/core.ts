import type { Address } from "viem";
import {
  checkNewDmConversationAllowed as defaultCheckGate,
  resolveProfiles as defaultResolveProfiles,
} from "./uapi.js";
import type {
  DmConsent,
  DmMessage,
  DmSummary,
  MessagingClient,
  MessagingProfile,
} from "./types.js";

/**
 * UI-agnostic orchestration for the DM commands. Combines the XMTP
 * `MessagingClient` with UAPI profile resolution and the new-conversation gate.
 * Mirrors the logic of the web app's `modules/messaging/core.ts`, minus React/
 * Relay. UAPI calls are injected (with real defaults) so this is unit-testable
 * with fakes and without loading the XMTP native binding.
 */

export interface CoreDeps {
  resolveProfiles: typeof defaultResolveProfiles;
  checkNewDmConversationAllowed: typeof defaultCheckGate;
}

const DEFAULT_DEPS: CoreDeps = {
  resolveProfiles: defaultResolveProfiles,
  checkNewDmConversationAllowed: defaultCheckGate,
};

/** Thrown when the new-conversation gate denies a send (rate limit / token gate). */
export class NewConversationDeniedError extends Error {
  readonly retryAfterSeconds: number;
  constructor(recipient: Address, retryAfterSeconds: number) {
    super(
      `Not allowed to start a new conversation with ${recipient}` +
        (retryAfterSeconds > 0 ? ` (retry after ${retryAfterSeconds}s)` : ""),
    );
    this.name = "NewConversationDeniedError";
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

interface ListOptions {
  token?: string;
  deps?: CoreDeps;
  /** Reports profile-lookup progress (uncached only) so callers can show "[n of m]". */
  onProfileProgress?: (done: number, total: number) => void;
}

const attachProfiles = async (
  summaries: DmSummary[],
  token: string | undefined,
  deps: CoreDeps,
  onProgress?: (done: number, total: number) => void,
): Promise<DmSummary[]> => {
  const addresses = summaries
    .map((s) => s.peerAddress)
    .filter((a): a is Address => a !== null);
  if (addresses.length === 0) return summaries;

  // Only pass onProgress when present, so the default 2-arg call shape is preserved.
  const profiles = onProgress
    ? await deps.resolveProfiles(addresses, token, onProgress)
    : await deps.resolveProfiles(addresses, token);
  return summaries.map((summary) => ({
    ...summary,
    profile: summary.peerAddress
      ? (profiles.get(summary.peerAddress) ?? null)
      : null,
  }));
};

/** Synced list of allowed conversations with resolved profiles (`zora dm list`). */
export const listConversations = async (
  client: MessagingClient,
  { token, deps = DEFAULT_DEPS, onProfileProgress }: ListOptions = {},
): Promise<DmSummary[]> => {
  await client.sync(["allowed"]);
  const dms = await client.listDms(["allowed"]);
  return attachProfiles(dms, token, deps, onProfileProgress);
};

/** Synced list of inbound requests (unknown consent) with profiles (`zora dm requests`). */
export const listRequests = async (
  client: MessagingClient,
  { token, deps = DEFAULT_DEPS, onProfileProgress }: ListOptions = {},
): Promise<DmSummary[]> => {
  await client.sync(["unknown"]);
  const dms = await client.listDms(["unknown"]);
  return attachProfiles(dms, token, deps, onProfileProgress);
};

export interface Conversation {
  profile: MessagingProfile | null;
  messages: DmMessage[];
}

/** Message history for one conversation, oldest-first, with the peer's profile. */
export const readConversation = async (
  client: MessagingClient,
  peerAddress: Address,
  { token, limit, deps = DEFAULT_DEPS }: ListOptions & { limit?: number } = {},
): Promise<Conversation> => {
  // Sync first so a direct `zora dm read <peer>` doesn't show stale messages,
  // matching listConversations/listRequests. A conversation can be allowed or an
  // unknown-consent request, so sync both.
  await client.sync(["allowed", "unknown"]);
  const [messages, profiles] = await Promise.all([
    client.readMessages(peerAddress, limit),
    deps.resolveProfiles([peerAddress], token),
  ]);
  // node-sdk returns newest-first; present oldest-first for reading.
  const ordered = [...messages].sort((a, b) => a.sentAtMs - b.sentAtMs);
  return { profile: profiles.get(peerAddress) ?? null, messages: ordered };
};

/**
 * Sends a text reply, creating the conversation if needed. When a token is
 * present, brand-new conversations are gated via `checkNewDmConversationAllowed`
 * and a denial throws `NewConversationDeniedError`. Without a token (dev/EOA
 * mode, no Privy JWT) the gate is skipped — the caller should warn.
 */
export const sendReply = async (
  client: MessagingClient,
  peerAddress: Address,
  text: string,
  { token, deps = DEFAULT_DEPS }: ListOptions = {},
): Promise<DmMessage> => {
  const gate = token
    ? async (recipient: Address): Promise<void> => {
        const result = await deps.checkNewDmConversationAllowed(
          recipient,
          token,
        );
        if (!result.allowed) {
          throw new NewConversationDeniedError(
            recipient,
            result.retryAfterSeconds,
          );
        }
      }
    : undefined;
  return client.sendText(peerAddress, text, gate);
};

/** Approve/deny a conversation by setting its consent state. */
export const setConsentForPeer = (
  client: MessagingClient,
  peerAddress: Address,
  consent: DmConsent,
): Promise<void> => client.setConsent(peerAddress, consent);
