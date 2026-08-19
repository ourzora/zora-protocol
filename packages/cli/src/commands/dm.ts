import { spawn } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { Command } from "commander";
import { isAddress, type Address } from "viem";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { getConfigDir, getPrivateKey } from "../lib/config.js";
import { normalizeKey } from "../lib/wallet.js";
import {
  formatError,
  bannedProfileMessage,
  serializeError,
} from "../lib/errors.js";
import { track } from "../lib/analytics.js";
import { createSmartWalletAuth } from "../messaging/identity.js";
import { createCliSmartWalletProvider } from "../messaging/cli-auth-provider.js";
import {
  registerXmtpInstallation,
  resolveProfiles,
  resolveHandleToAddress,
} from "../messaging/uapi.js";
import {
  isInstallationLimitError,
  isNativeBindingError,
  nativeBindingErrorHelp,
} from "../messaging/native-binding.js";
import {
  NewConversationDeniedError,
  type Conversation,
  listConversations,
  listRequests,
  readConversation,
  sendReply,
  setConsentForPeer,
} from "../messaging/core.js";
import {
  callDmIpc,
  startDmIpcServer,
  dmSocketPath,
  type DmIpcRequest,
} from "../messaging/ipc.js";
import type {
  DmConsent,
  DmMessage,
  DmSummary,
  InstallationInfo,
  MessagingClient,
} from "../messaging/types.js";

/** A message as yielded by {@link MessagingClient.streamAllMessages}. */
type StreamedDm = DmMessage & {
  peerAddress: Address | null;
  consent: DmConsent;
};

/**
 * `zora dm` — read and respond to Zora DMs from the CLI.
 *
 * DMs run from the user's shared Coinbase Smart Wallet inbox (the same inbox the
 * web/mobile apps use), authenticated as their Zora identity via Privy. This
 * requires a provisioned smart wallet, so the command guides the user to
 * `zora agent create` when one isn't available.
 */

interface ResolvedClient {
  client: MessagingClient;
  /**
   * Privy JWT for authenticated UAPI calls. Always present at runtime in
   * smart-wallet mode; typed optional to match the `MessagingAuth` contract.
   */
  token: string | undefined;
}

const resolveClient = async (json: boolean): Promise<ResolvedClient> => {
  const key = process.env.ZORA_PRIVATE_KEY || getPrivateKey();
  if (!key) {
    return outputErrorAndExit(
      json,
      "No wallet configured.",
      "Run 'zora agent create' to set up your Zora agent.",
    );
  }

  let auth;
  try {
    const provider = await createCliSmartWalletProvider({
      privateKey: normalizeKey(key),
    });
    auth = createSmartWalletAuth(provider);
  } catch (err) {
    return outputErrorAndExit(
      json,
      "Couldn't authenticate your Zora smart-wallet inbox.",
      formatError(err),
    );
  }

  const token = await auth.getApiToken();
  // Imported lazily so the XMTP native binding (@xmtp/node-bindings, loaded by
  // client.js) is only required when a dm subcommand actually runs — not at CLI
  // startup. Keeps `zora --help` and every non-dm command working without it.
  //
  // The import itself triggers the native binding load, so it — and the
  // createMessagingClient call that uses it — are the two places a binding-load
  // failure surfaces. On common LTS Linux servers (Ubuntu 22.04, Debian 12, many
  // GCP/VPS images) the prebuilt binding's glibc is too new and dlopen fails with
  // a cryptic, nested "cannot find native binding" error. Catch it and explain
  // how to run DMs instead of crashing with a stack trace. See native-binding.ts.
  let client: MessagingClient;
  try {
    const { createMessagingClient } = await import("../messaging/client.js");
    client = await createMessagingClient(auth.signerSpec, {
      // Register the CLI installation with the Zora backend so it shows up in the
      // user's device list and counts against the install cap. Best-effort — see
      // client.ts. (The smart-wallet auth layer always provides a token.)
      registerInstallation: token
        ? (installationId) => registerXmtpInstallation(installationId, token)
        : undefined,
    });
  } catch (err) {
    if (isNativeBindingError(err)) {
      return outputErrorAndExit(
        json,
        "DMs aren't available in this environment.",
        nativeBindingErrorHelp(),
      );
    }
    if (isInstallationLimitError(err)) {
      return outputErrorAndExit(
        json,
        "Your Zora inbox is at its 10-device (XMTP installation) limit, so a new one can't be registered.",
        "Free a slot from the CLI: `zora dm installations` to list your devices, then `zora dm revoke <id>` to remove an old one. (The background `dm listen` uses its own device, so it needs a free slot.)",
      );
    }
    throw err;
  }
  return { client, token };
};

/**
 * Run a DM operation against the single owning client. When a `dm listen`
 * process is running, forward the op to it over IPC so its one client executes
 * it — no second client/installation, so local state can't diverge. With no
 * live listener, run `direct` (a short-lived client opened here). A dead/absent
 * listener makes {@link callDmIpc} return null, so we fall back to `direct`.
 */
const dmOp = async <T>(
  op: string,
  args: Record<string, unknown>,
  direct: () => Promise<T>,
): Promise<T> => {
  const res = await callDmIpc({ op, args });
  if (res === null) return direct();
  if (res.ok) return res.data as T;
  const err = new Error(
    res.error?.message ?? "DM operation failed",
  ) as Error & { retryAfterSeconds?: number };
  if (res.error?.name) err.name = res.error.name;
  if (typeof res.error?.retryAfterSeconds === "number") {
    err.retryAfterSeconds = res.error.retryAfterSeconds;
  }
  throw err;
};

/** True for a new-conversation-gate denial from either the direct or IPC path. */
const isNewConversationDenied = (
  err: unknown,
): err is { retryAfterSeconds: number; message: string } =>
  err instanceof NewConversationDeniedError ||
  (err instanceof Error && err.name === "NewConversationDeniedError");

/** `@handle` for a peer when it has a Zora profile, else the address. Cached + best-effort. */
const peerLabel = async (peer: Address): Promise<string> => {
  try {
    const handle = (await resolveProfiles([peer])).get(peer)?.handle;
    return handle ? `@${handle}` : peer;
  } catch {
    return peer;
  }
};

/**
 * Resolve a peer argument that may be a `0x` address or a Zora handle (`@name`
 * or `name`). Handles are looked up to the user's smart-wallet DM address.
 */
const resolvePeer = async (json: boolean, value: string): Promise<Address> => {
  if (isAddress(value)) return value as Address;
  const result = await resolveHandleToAddress(value);
  if (result.ok) return result.address;

  const messages: Record<typeof result.reason, [string, string]> = {
    "not-found": [
      `No Zora account found for "${value}".`,
      "Check the handle, or pass a 0x address.",
    ],
    "no-inbox": [
      `"${value}" doesn't have a Zora DM inbox yet.`,
      "They need a Zora smart wallet to receive DMs.",
    ],
    error: [
      `Couldn't reach Zora to resolve "${value}".`,
      "Check your connection and try again.",
    ],
  };
  const [message, suggestion] = messages[result.reason];
  return outputErrorAndExit(json, message, suggestion);
};

const summaryToJson = (s: DmSummary) => ({
  id: s.id,
  address: s.peerAddress,
  handle: s.profile?.handle ?? null,
  consent: s.consent,
  lastMessage: s.lastMessage
    ? {
        text: s.lastMessage.text,
        fromSelf: s.lastMessage.fromSelf,
        sentAt: new Date(s.lastMessage.sentAtMs).toISOString(),
      }
    : null,
});

/**
 * Strip control + escape characters from untrusted DM text before printing, so a
 * peer can't inject ANSI/terminal sequences. Keeps tabs and newlines. (DMs are
 * plain text — there is no markdown/HTML to render, just raw characters.)
 */
export const sanitizeMessageText = (text: string): string => {
  // Keep tab (9) and newline (10); drop other C0 control chars and DEL (127),
  // so an untrusted peer can't inject ANSI/terminal escape sequences.
  let out = "";
  for (const ch of text) {
    const code = ch.codePointAt(0) ?? 0;
    if (code === 9 || code === 10 || (code >= 32 && code !== 127)) out += ch;
  }
  return out;
};

/** A single-line, length-capped preview of a message body for list views. */
export const messagePreview = (text: string, max = 72): string => {
  const clean = sanitizeMessageText(text).replace(/\s+/g, " ").trim();
  return clean.length > max ? `${clean.slice(0, max - 1)}…` : clean;
};

/** Compact relative age of an XMTP message from its `sentAtMs` (e.g. "2h ago"). */
export const formatAge = (sentAtMs: number, nowMs = Date.now()): string => {
  const s = Math.max(0, Math.floor((nowMs - sentAtMs) / 1000));
  if (s < 45) return "just now";
  const m = Math.round(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.round(h / 24);
  if (d < 7) return `${d}d ago`;
  const w = Math.round(d / 7);
  if (w < 5) return `${w}w ago`;
  return new Date(sentAtMs).toISOString().slice(0, 10);
};

/** Dim grey wrapper for secondary text. */
const dim = (s: string): string => `\x1b[2m${s}\x1b[0m`;

/**
 * Stderr progress for the inbox/requests commands so the user knows how long to
 * wait: a brief "syncing" status, then a "[n of m]" counter over the (uncached)
 * handle lookups. No-op for `--json` or a non-TTY (pipes/CI); `done()` clears it.
 */
const startInboxProgress = (json: boolean) => {
  const active = !json && process.stderr.isTTY;
  if (active) process.stderr.write("Syncing your inbox…");
  let finished = false;
  return {
    update(done: number, total: number) {
      if (active && !finished) {
        process.stderr.write(
          `\r\x1b[K[${done} of ${total}] resolving handles…`,
        );
      }
    },
    done() {
      if (active && !finished) {
        finished = true;
        process.stderr.write("\r\x1b[K");
      }
    },
  };
};

const renderSummaries = (summaries: DmSummary[], empty: string): void => {
  if (summaries.length === 0) {
    console.log(empty);
    return;
  }
  for (const s of summaries) {
    const who = s.profile?.handle
      ? `@${s.profile.handle}`
      : (s.peerAddress ?? "unknown");
    const age = s.lastMessage
      ? ` ${dim(formatAge(s.lastMessage.sentAtMs))}`
      : "";
    // One-line preview so a long/multi-line message can't blow up the list.
    const preview = s.lastMessage?.text
      ? `${s.lastMessage.fromSelf ? "→ " : "← "}${messagePreview(s.lastMessage.text)}`
      : "(no messages)";
    // Show the handle (or the address only when there's no handle) — never both.
    console.log(`${who}${age}\n  ${preview}`);
  }
};

export const dmCommand = new Command("dm")
  .description("Read and respond to your Zora DMs")
  .action(function (this: Command) {
    this.outputHelp();
  });

dmCommand
  .command("list")
  .description("List active conversations")
  .action(async function (this: Command) {
    const json = getJson(this);
    const progress = startInboxProgress(json);
    try {
      const conversations = await dmOp<DmSummary[]>("list", {}, async () => {
        const { client, token } = await resolveClient(json);
        try {
          return await listConversations(client, {
            token,
            onProfileProgress: progress.update,
          });
        } finally {
          await client.close();
        }
      });
      progress.done();
      outputData(json, {
        json: conversations.map(summaryToJson),
        render: () => renderSummaries(conversations, "No conversations yet."),
      });
      track("cli_dm_list", {
        count: conversations.length,
        output_format: json ? "json" : "text",
      });
    } finally {
      progress.done();
    }
  });

dmCommand
  .command("requests")
  .description("List inbound message requests (pending your approval)")
  .action(async function (this: Command) {
    const json = getJson(this);
    const progress = startInboxProgress(json);
    try {
      const requests = await dmOp<DmSummary[]>("requests", {}, async () => {
        const { client, token } = await resolveClient(json);
        try {
          return await listRequests(client, {
            token,
            onProfileProgress: progress.update,
          });
        } finally {
          await client.close();
        }
      });
      progress.done();
      outputData(json, {
        json: requests.map(summaryToJson),
        render: () => renderSummaries(requests, "No pending requests."),
      });
      track("cli_dm_requests", {
        count: requests.length,
        output_format: json ? "json" : "text",
      });
    } finally {
      progress.done();
    }
  });

dmCommand
  .command("read")
  .description("Read the message history of a conversation")
  .argument("<address>", "Zora handle (@name) or 0x address")
  .option("--limit <n>", "Max messages to fetch", "30")
  .action(async function (
    this: Command,
    address: string,
    opts: { limit: string },
  ) {
    const json = getJson(this);
    const peer = await resolvePeer(json, address);
    const limit = Number.parseInt(opts.limit, 10) || 30;
    const { profile, messages } = await dmOp<Conversation>(
      "read",
      { peer, limit },
      async () => {
        const { client, token } = await resolveClient(json);
        try {
          return await readConversation(client, peer, { token, limit });
        } finally {
          await client.close();
        }
      },
    );
    outputData(json, {
      json: {
        peer: { address: peer, handle: profile?.handle ?? null },
        messages: messages.map((m) => ({
          from: m.fromSelf ? "self" : "peer",
          text: m.text,
          contentType: m.contentType,
          sentAt: new Date(m.sentAtMs).toISOString(),
        })),
      },
      render: () => {
        const who = profile?.handle ? `@${profile.handle}` : peer;
        console.log(`Conversation with ${who}\n`);
        if (messages.length === 0) console.log("(no messages)");
        for (const m of messages) {
          const arrow = m.fromSelf ? "→" : "←";
          const body = m.text
            ? sanitizeMessageText(m.text)
            : `[${m.contentType}]`;
          // Multi-line messages: indent continuation lines to align under the text.
          const [first = "", ...rest] = body.split("\n");
          console.log(`${arrow} ${first} ${dim(formatAge(m.sentAtMs))}`);
          for (const line of rest) console.log(`  ${line}`);
        }
      },
    });
    track("cli_dm_read", {
      count: messages.length,
      output_format: json ? "json" : "text",
    });
  });

dmCommand
  .command("send")
  .description(
    "Send a plain-text reply (DMs are plain text; gated for brand-new conversations)",
  )
  .argument("<address>", "Recipient: Zora handle (@name) or 0x address")
  .argument("[message]", "Message text")
  .action(async function (this: Command, address: string, message: string) {
    const json = getJson(this);
    const peer = await resolvePeer(json, address);

    // Block interaction with platform-banned profiles
    const profiles = await resolveProfiles([peer]);
    const profile = profiles.get(peer);
    if (profile?.platformBlocked) {
      track("cli_dm_send", {
        output_format: json ? "json" : "text",
        success: false,
        blocked_profile: true,
      });
      return outputErrorAndExit(
        json,
        bannedProfileMessage(profile.handle ?? peer),
      );
    }

    if (!message || !message.trim()) {
      return outputErrorAndExit(
        json,
        "Message text is required.",
        'Usage: zora dm send <address> "your message"',
      );
    }
    try {
      const sent = await dmOp<DmMessage>(
        "send",
        { peer, text: message },
        async () => {
          const { client, token } = await resolveClient(json);
          try {
            return await sendReply(client, peer, message, { token });
          } finally {
            await client.close();
          }
        },
      );
      const label = await peerLabel(peer);
      outputData(json, {
        json: { sent: true, to: peer, id: sent.id, text: sent.text },
        render: () => console.log(`Sent to ${label}: ${sent.text}`),
      });
      track("cli_dm_send", {
        output_format: json ? "json" : "text",
        success: true,
      });
    } catch (err) {
      if (isNewConversationDenied(err)) {
        track("cli_dm_send", {
          output_format: json ? "json" : "text",
          success: false,
          denied: true,
          error: serializeError(err),
        });
        return outputErrorAndExit(
          json,
          err.message,
          err.retryAfterSeconds > 0
            ? `Try again in ${err.retryAfterSeconds}s.`
            : undefined,
        );
      }
      throw err;
    }
  });

/** Classify a streamed message: a first message from a stranger is a request. */
export const dmType = (consent: DmConsent): "DM" | "DM_REQUEST" =>
  consent === "unknown" ? "DM_REQUEST" : "DM";

/**
 * Whether an inbound message should fire the `--exec` hook. Fires for any text
 * message — an active DM *or* a first message from a stranger (`unknown`
 * consent, i.e. a request) — so a new request wakes the agent exactly like an
 * ongoing conversation. Whether to then approve, reply, or deny it is the
 * owner's triage policy, not a network-level filter. Skips non-text events
 * (reactions/read-receipts) and conversations the owner has explicitly denied.
 */
export const shouldExecForMessage = (msg: {
  text: string | null;
  consent: DmConsent;
}): boolean => {
  if (!msg.text || !msg.text.trim()) return false;
  if (msg.consent === "denied") return false;
  return true; // allowed OR unknown (a request) both wake the agent
};

/** A prior message in the thread, carried in the `--exec` payload for context. */
export interface ExecHistoryEntry {
  /** `"me"` for the agent's own messages, else the peer's label (`@handle`/address). */
  from: string;
  text: string | null;
  /** ISO 8601 timestamp. */
  sentAt: string;
}

/** The thread context for one `--exec` payload — the messages plus the gap. */
export interface ExecHistoryResult {
  history: ExecHistoryEntry[];
  /**
   * Hours since the peer's most recent prior message, set only when the thread
   * was idle past the window and `history` fell back to the tail of the previous
   * conversation — the "it's been ~X hours since we last talked" signal so a
   * resumed conversation reads as a resumption. `null` for an active thread
   * (messages within the window) or a first-ever contact.
   */
  hoursSinceLastMessage: number | null;
}

/**
 * JSON handed to the `--exec` hook via `$ZORA_DM`; untrusted text is sanitized.
 * `history` carries prior messages in the same thread (oldest first) so a fresh
 * per-message agent turn has the conversation, not just the one message; when
 * that history is a post-gap fallback, `hoursSinceLastMessage` says how stale it
 * is so the agent can acknowledge the gap.
 */
export const buildExecPayload = (
  msg: StreamedDm,
  from: string,
  history: ExecHistoryEntry[] = [],
  hoursSinceLastMessage: number | null = null,
): string =>
  JSON.stringify({
    type: dmType(msg.consent),
    consent: msg.consent,
    from,
    address: msg.peerAddress,
    text: msg.text ? sanitizeMessageText(msg.text) : null,
    contentType: msg.contentType,
    sentAt: new Date(msg.sentAtMs).toISOString(),
    hoursSinceLastMessage,
    history: history.map((h) => ({
      from: h.from,
      text: h.text ? sanitizeMessageText(h.text) : null,
      sentAt: h.sentAt,
    })),
  });

/**
 * Parse a duration like `1h`, `30m`, `24h`, `2d`, or `90s` to milliseconds.
 * `0` (also `off`/`none`) means disabled → `0`. Returns `null` if unparseable,
 * so the caller can reject a typo rather than silently pick a window.
 */
export const parseDurationMs = (value: string): number | null => {
  const t = value.trim().toLowerCase();
  if (t === "0" || t === "off" || t === "none") return 0;
  const m = /^(\d+)(s|m|h|d)$/.exec(t);
  if (!m) return null;
  const mult = { s: 1_000, m: 60_000, h: 3_600_000, d: 86_400_000 }[m[2]]!;
  return Number(m[1]) * mult;
};

/** Cap on messages in one `--exec` history, guarding a busy window's payload. */
export const EXEC_HISTORY_MAX_MESSAGES = 200;

/** Messages to fall back to when the window is empty (a resumed conversation). */
export const EXEC_HISTORY_FALLBACK_COUNT = 10;

/**
 * Build the thread context for an `--exec` payload from the messages read out of
 * the local store. Only text messages count — reactions, receipts, and the
 * conversation-init message XMTP opens every DM with are dropped (the same
 * text-only filter the fire gate {@link shouldExecForMessage} uses), so context
 * is real conversation, not protocol noise. Then:
 *
 * - **Active thread** — messages sent within `windowMs` before `nowMs`: return
 *   them (oldest first, capped at {@link EXEC_HISTORY_MAX_MESSAGES}), no gap.
 * - **Resumed thread** — nothing in the window but earlier messages exist: fall
 *   back to the last {@link EXEC_HISTORY_FALLBACK_COUNT} so the agent still has
 *   the prior conversation, and set `hoursSinceLastMessage` so it can see it's
 *   been a while and greet accordingly.
 * - **First contact** — no prior messages: empty, no gap.
 */
export const selectExecHistory = (
  messages: DmMessage[],
  currentId: string,
  peerLabel: string,
  nowMs: number,
  windowMs: number,
  fallbackCount: number = EXEC_HISTORY_FALLBACK_COUNT,
): ExecHistoryResult => {
  const toEntry = (m: DmMessage): ExecHistoryEntry => ({
    from: m.fromSelf ? "me" : peerLabel,
    text: m.text,
    sentAt: new Date(m.sentAtMs).toISOString(),
  });

  const prior = messages
    .filter((m) => m.id !== currentId && m.text && m.text.trim())
    .sort((a, b) => a.sentAtMs - b.sentAtMs);
  if (prior.length === 0) return { history: [], hoursSinceLastMessage: null };

  const inWindow = prior.filter((m) => m.sentAtMs >= nowMs - windowMs);
  if (inWindow.length > 0) {
    return {
      history: inWindow.slice(-EXEC_HISTORY_MAX_MESSAGES).map(toEntry),
      hoursSinceLastMessage: null,
    };
  }

  // Idle past the window — hand over the tail of the last conversation, dated.
  const gapMs = nowMs - prior[prior.length - 1].sentAtMs;
  return {
    history: prior.slice(-fallbackCount).map(toEntry),
    hoursSinceLastMessage: Math.round((gapMs / 3_600_000) * 10) / 10,
  };
};

const listenerLockPath = (): string =>
  join(getConfigDir(), "xmtp", "listener.lock");

const isPidAlive = (pid: number): boolean => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

/**
 * Enforce a single background listener per machine: two listeners on the same
 * local store would recreate the multi-process XMTP hazard the dedicated
 * installation exists to avoid. Returns a live holder's PID if one already
 * runs, or null after taking the lock.
 */
const acquireListenerLock = (): number | null => {
  const path = listenerLockPath();
  const dir = dirname(path);
  mkdirSync(dir, { recursive: true });
  // Owner-only, same rationale as the IPC socket dir (see startDmIpcServer): the
  // xmtp/ dir also holds the encrypted XMTP stores. This runs before the IPC
  // server, so lock the dir down here too rather than leaving a window under a
  // permissive umask. Best-effort — chmod is a no-op on non-POSIX filesystems.
  try {
    chmodSync(dir, 0o700);
  } catch {
    // non-POSIX filesystem — nothing to restrict
  }
  if (existsSync(path)) {
    const pid = Number.parseInt(readFileSync(path, "utf8").trim(), 10);
    if (Number.isFinite(pid) && pid !== process.pid && isPidAlive(pid)) {
      return pid;
    }
  }
  writeFileSync(path, String(process.pid), { mode: 0o600 });
  return null;
};

const releaseListenerLock = (): void => {
  try {
    const path = listenerLockPath();
    // Only remove it if we still own it, so we never delete a replacement
    // listener's lock.
    if (
      existsSync(path) &&
      readFileSync(path, "utf8").trim() === String(process.pid)
    ) {
      rmSync(path);
    }
  } catch {
    // best-effort
  }
};

dmCommand
  .command("listen")
  .description(
    "Stream incoming DMs/requests in real time and optionally run a hook per message. Owns the XMTP client while running: one-shot `dm` commands route through it (over a local socket), so there's no second installation and no divergence.",
  )
  .option(
    "--exec <cmd>",
    "Run this command for each new DM/request (message JSON passed as $ZORA_DM) — use it to wake an agent in real time",
  )
  .option(
    "--exec-history <window>",
    "How much recent thread history to put in each --exec payload's `history`, as a time window (e.g. 30m, 1h, 24h) so a per-message agent has conversation context. Empty window falls back to the last few messages. 0 disables.",
    "30m",
  )
  .action(async function (
    this: Command,
    opts: { exec?: string; execHistory?: string },
  ) {
    const json = getJson(this);
    const execCmd = opts.exec;
    // History is a time window (default 30m): an agent turn gets every message in
    // the last half hour of the thread, not a fixed count. Validate before taking
    // the lock / building the client, so a typo fails fast without side effects.
    const execHistoryWindowMs = parseDurationMs(opts.execHistory ?? "30m");
    if (execHistoryWindowMs === null) {
      return outputErrorAndExit(
        json,
        `Invalid --exec-history: "${opts.execHistory}".`,
        "Pass a time window like 30m, 1h, or 24h (0 disables).",
      );
    }

    // Single-instance guard — before building the client, so we fail fast.
    const holder = acquireListenerLock();
    if (holder !== null) {
      return outputErrorAndExit(
        json,
        `A DM listener is already running (pid ${holder}).`,
        "Only one listener can run at a time; stop the other first.",
      );
    }
    // Release the lock on ANY exit path — including a clean `outputErrorAndExit`
    // (e.g. the install-cap error) that happens before the try/finally below —
    // so a failed startup never leaves a stale lock behind.
    process.on("exit", releaseListenerLock);

    const { client, token } = await resolveClient(json);

    // Serve one-shot `dm` operations on the shared client so they don't open a
    // second client/installation. Ops run on the same client that's streaming —
    // the normal XMTP pattern (stream + send on one client, one process).
    const ipcServer = startDmIpcServer(async (req: DmIpcRequest) => {
      const a = req.args ?? {};
      switch (req.op) {
        case "list":
          return listConversations(client, { token });
        case "requests":
          return listRequests(client, { token });
        case "read":
          return readConversation(client, a.peer as Address, {
            token,
            limit: a.limit as number | undefined,
          });
        case "send":
          return sendReply(client, a.peer as Address, a.text as string, {
            token,
          });
        case "approve":
          return setConsentForPeer(client, a.peer as Address, "allowed");
        case "deny":
          return setConsentForPeer(client, a.peer as Address, "denied");
        case "installations":
          return client.listInstallations();
        case "revoke":
          return client.revokeInstallations(a.ids as string[]);
        case "revokeOthers":
          return client.revokeOtherInstallations();
        default:
          throw new Error(`Unknown DM op: ${req.op}`);
      }
    });

    if (!json) {
      console.log(
        `Listening for new DMs${execCmd ? " (running your hook per message)" : ""}… (Ctrl+C to stop)\n`,
      );
    }

    let messageCount = 0;
    let shuttingDown = false;
    // End-analytics + cleanup, run exactly once — on graceful shutdown OR normal
    // loop exit. Must run *before* the shutdown handler's process.exit, or the
    // end event is dropped (client.close() resolves as a microtask, so exit
    // would otherwise fire before the loop's finally block).
    let finalized = false;
    const finalize = () => {
      if (finalized) return;
      finalized = true;
      track("cli_dm_listen_end", {
        output_format: json ? "json" : "text",
        message_count: messageCount,
      });
      ipcServer.close();
      try {
        rmSync(dmSocketPath());
      } catch {
        // socket already gone
      }
      releaseListenerLock();
    };
    const shutdown = () => {
      shuttingDown = true;
      finalize();
      client.close().finally(() => process.exit(0));
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    // Resolve the peer's handle for display + the `--exec` payload, cached so a
    // high-traffic stream doesn't do a profile lookup per message.
    const labelCache = new Map<string, string>();
    const cachedPeerLabel = async (peer: Address): Promise<string> => {
      const cached = labelCache.get(peer);
      if (cached) return cached;
      const label = await peerLabel(peer);
      labelCache.set(peer, label);
      return label;
    };

    // Prior messages in the thread for the `--exec` payload, so a fresh
    // per-message agent turn has conversation context — not just the single new
    // message. Read from the local store the stream already keeps synced (no
    // network); best-effort: a read failure must never drop the wake, just send
    // it without history. selectExecHistory applies the window / gap-fallback.
    const threadHistory = async (
      msg: StreamedDm,
      peerLabelStr: string,
    ): Promise<ExecHistoryResult> => {
      const empty: ExecHistoryResult = {
        history: [],
        hoursSinceLastMessage: null,
      };
      if (execHistoryWindowMs <= 0 || !msg.peerAddress) return empty;
      try {
        // Fetch the cap's worth so a busy window is covered; older and non-text
        // messages are filtered out in selectExecHistory.
        const prior = await client.readMessages(
          msg.peerAddress,
          EXEC_HISTORY_MAX_MESSAGES,
        );
        return selectExecHistory(
          prior,
          msg.id,
          peerLabelStr,
          msg.sentAtMs,
          execHistoryWindowMs,
        );
      } catch {
        return empty;
      }
    };

    // Back-pressure for `--exec`: run the hook one invocation at a time and
    // queue the rest, so a slow hook under a burst can't spawn an unbounded pile
    // of concurrent processes. Enqueuing never blocks the stream. The backlog is
    // capped so sustained spam against a stuck hook can't grow memory without
    // bound — dropped events are still recoverable via `dm list`.
    const EXEC_BACKLOG_MAX = 100;
    const execQueue: string[] = [];
    let execRunning = false;
    const drainExec = (cmd: string): void => {
      if (execRunning) return;
      const payload = execQueue.shift();
      if (payload === undefined) return;
      execRunning = true;
      let settled = false;
      const next = () => {
        if (settled) return;
        settled = true;
        execRunning = false;
        drainExec(cmd);
      };
      try {
        const child = spawn(cmd, {
          shell: true,
          stdio: "ignore",
          // Payload travels via env, never interpolated into the shell string,
          // so untrusted DM text can't inject shell commands.
          env: { ...process.env, ZORA_DM: payload },
        });
        child.once("error", next); // a failing hook must never break capture
        child.once("exit", next);
        child.unref();
      } catch {
        next();
      }
    };
    const fireExec = (cmd: string, payload: string, from: string): void => {
      execQueue.push(payload);
      if (execQueue.length > EXEC_BACKLOG_MAX) {
        execQueue.shift(); // drop the oldest to make room, bounding memory
        if (!json) {
          // Warn (not error): capture continues. Name the triggering peer and
          // this session's message number so the drop is actionable amid many
          // active threads; dropped events are still recoverable via `dm list`.
          console.warn(
            `--exec backlog full (${EXEC_BACKLOG_MAX}); dropped the oldest queued event to make room for the message from ${from} (msg #${messageCount}) — recover dropped events via \`dm list\``,
          );
        }
      }
      drainExec(cmd);
    };

    track("cli_dm_listen_start", {
      output_format: json ? "json" : "text",
      exec: Boolean(execCmd),
      exec_history_ms: execCmd ? execHistoryWindowMs : 0,
    });

    const handleMessage = async (msg: StreamedDm): Promise<void> => {
      if (msg.fromSelf) return;
      messageCount++;
      const type = dmType(msg.consent);
      const label = msg.peerAddress
        ? await cachedPeerLabel(msg.peerAddress)
        : "unknown";

      if (json) {
        console.log(
          JSON.stringify({
            type,
            consent: msg.consent,
            from: label,
            address: msg.peerAddress,
            text: msg.text,
            contentType: msg.contentType,
            sentAt: new Date(msg.sentAtMs).toISOString(),
          }),
        );
      } else {
        const body = msg.text
          ? sanitizeMessageText(msg.text)
          : `[${msg.contentType}]`;
        const [first = "", ...rest] = body.split("\n");
        const tag = type === "DM_REQUEST" ? "📨 request " : "";
        console.log(
          `${tag}← ${label} ${dim(formatAge(msg.sentAtMs))}\n  ${first}`,
        );
        for (const line of rest) console.log(`  ${line}`);
        if (type === "DM_REQUEST") {
          console.log(`  ${dim(`approve to reply: zora dm approve ${label}`)}`);
        }
      }

      if (execCmd && shouldExecForMessage(msg)) {
        const { history, hoursSinceLastMessage } = await threadHistory(
          msg,
          label,
        );
        fireExec(
          execCmd,
          buildExecPayload(msg, label, history, hoursSinceLastMessage),
          label,
        );
      }
    };

    try {
      // Reconnect with capped backoff so a long-lived listener survives
      // transient stream drops. Known gap: messages that arrive *during* a drop
      // are synced to the local store but not re-emitted by the next live
      // stream — a persisted catch-up cursor is a planned follow-up (see the PR
      // description).
      let backoffMs = 1000;
      while (!shuttingDown) {
        let errored = false;
        try {
          for await (const msg of client.streamAllMessages()) {
            if (shuttingDown) break;
            backoffMs = 1000; // reset after a successful delivery
            await handleMessage(msg);
          }
        } catch (err) {
          errored = true;
          if (shuttingDown) break;
          if (!json) {
            console.error(
              dim(
                `Stream dropped, reconnecting in ${Math.round(backoffMs / 1000)}s: ${(err as Error).message}`,
              ),
            );
          }
        }
        // Reconnect only on error. A clean stream completion means the caller
        // ended it (shutdown, or a bounded stream) — stop rather than spin.
        if (shuttingDown || !errored) break;
        await new Promise((resolve) => setTimeout(resolve, backoffMs));
        backoffMs = Math.min(backoffMs * 2, 30_000);
      }
    } finally {
      finalize();
      await client.close();
    }
  });

dmCommand
  .command("installations")
  .alias("devices")
  .description(
    "List the XMTP installations (devices) on your inbox — you can have up to 10",
  )
  .action(async function (this: Command) {
    const json = getJson(this);
    const installations = await dmOp<InstallationInfo[]>(
      "installations",
      {},
      async () => {
        const { client } = await resolveClient(json);
        try {
          return await client.listInstallations();
        } finally {
          await client.close();
        }
      },
    );
    // Oldest first: the likeliest stale ones to revoke sort to the top.
    installations.sort((a, b) => (a.createdAtMs ?? 0) - (b.createdAtMs ?? 0));
    outputData(json, {
      json: installations.map((i) => ({
        id: i.id,
        createdAt: i.createdAtMs ? new Date(i.createdAtMs).toISOString() : null,
        current: i.current,
      })),
      render: () => {
        console.log(`${installations.length} of 10 devices:`);
        for (const i of installations) {
          const when = i.createdAtMs
            ? `created ${formatAge(i.createdAtMs)}`
            : "created unknown";
          const tag = i.current ? " (this device)" : "";
          console.log(`  ${i.id}${tag} ${dim(when)}`);
        }
        if (installations.length >= 10) {
          console.log(
            dim(
              "\nAt the 10-device limit. Free a slot with `zora dm revoke <id>` before adding a new device (e.g. `dm listen`).",
            ),
          );
        }
      },
    });
    track("cli_dm_installations", {
      count: installations.length,
      output_format: json ? "json" : "text",
    });
  });

dmCommand
  .command("revoke")
  .description(
    "Revoke XMTP installations (devices) to free slots against the 10-device limit",
  )
  .argument(
    "[ids...]",
    "Installation id(s) to revoke (see `zora dm installations`)",
  )
  .option("--others", "Revoke every device except this one")
  .action(async function (
    this: Command,
    ids: string[],
    opts: { others?: boolean },
  ) {
    const json = getJson(this);
    if (!opts.others && ids.length === 0) {
      return outputErrorAndExit(
        json,
        "Nothing to revoke.",
        "Pass installation id(s) from `zora dm installations`, or use --others to revoke every other device.",
      );
    }
    try {
      if (opts.others) {
        await dmOp<null>("revokeOthers", {}, async () => {
          const { client } = await resolveClient(json);
          try {
            await client.revokeOtherInstallations();
            return null;
          } finally {
            await client.close();
          }
        });
        outputData(json, {
          json: { revoked: "others" },
          render: () =>
            console.log("Revoked all other devices; this one remains."),
        });
      } else {
        // Never revoke the device we're currently running as — that would cut
        // off this CLI's own access.
        const installations = await dmOp<InstallationInfo[]>(
          "installations",
          {},
          async () => {
            const { client } = await resolveClient(json);
            try {
              return await client.listInstallations();
            } finally {
              await client.close();
            }
          },
        );
        const currentId = installations.find((i) => i.current)?.id;
        const targets = ids.filter((id) => id !== currentId);
        const skippedCurrent = targets.length !== ids.length;
        if (targets.length === 0) {
          return outputErrorAndExit(
            json,
            "Refusing to revoke the current device.",
            "Pass a different installation id, or use --others to revoke every other device.",
          );
        }
        await dmOp<null>("revoke", { ids: targets }, async () => {
          const { client } = await resolveClient(json);
          try {
            await client.revokeInstallations(targets);
            return null;
          } finally {
            await client.close();
          }
        });
        outputData(json, {
          json: { revoked: targets, skippedCurrent },
          render: () => {
            console.log(`Revoked ${targets.length} device(s).`);
            if (skippedCurrent) {
              console.log(dim("Skipped the current device."));
            }
          },
        });
      }
      track("cli_dm_revoke", {
        others: Boolean(opts.others),
        output_format: json ? "json" : "text",
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      // Fail cleanly (rather than crashing) if XMTP rejects the revoke
      // signature for any reason, and point to the web fallback.
      if (/signature/i.test(message)) {
        return outputErrorAndExit(
          json,
          "Couldn't revoke: XMTP rejected the smart wallet's signature.",
          "If this persists, revoke the device in Settings → Messaging at zora.co.",
        );
      }
      return outputErrorAndExit(
        json,
        "Couldn't revoke installation(s).",
        message,
      );
    }
  });

const consentSubcommand = (
  name: "approve" | "deny",
  consent: DmConsent,
  description: string,
): void => {
  dmCommand
    .command(name)
    .description(description)
    .argument("<address>", "Zora handle (@name) or 0x address")
    .action(async function (this: Command, address: string) {
      const json = getJson(this);
      const peer = await resolvePeer(json, address);
      try {
        await dmOp<null>(name, { peer }, async () => {
          const { client } = await resolveClient(json);
          try {
            await setConsentForPeer(client, peer, consent);
            return null;
          } finally {
            await client.close();
          }
        });
        const label = await peerLabel(peer);
        outputData(json, {
          json: { address: peer, consent },
          render: () =>
            console.log(
              `Added ${label} to DM ${name === "approve" ? "allowlist" : "denylist"}`,
            ),
        });
        track(`cli_dm_${name}`, { output_format: json ? "json" : "text" });
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        if (/no conversation found/i.test(message)) {
          return outputErrorAndExit(
            json,
            `No conversation with ${await peerLabel(peer)} to ${name}.`,
            "They may not have messaged you yet. See `zora dm requests`.",
          );
        }
        throw err;
      }
    });
};

consentSubcommand("approve", "allowed", "Approve an inbound request");
consentSubcommand("deny", "denied", "Deny an inbound request");
