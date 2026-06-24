import { Command } from "commander";
import { isAddress, type Address } from "viem";
import { getJson, outputData, outputErrorAndExit } from "../lib/output.js";
import { getPrivateKey } from "../lib/config.js";
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
  isNativeBindingError,
  nativeBindingErrorHelp,
} from "../messaging/native-binding.js";
import {
  NewConversationDeniedError,
  listConversations,
  listRequests,
  readConversation,
  sendReply,
  setConsentForPeer,
} from "../messaging/core.js";
import type {
  DmConsent,
  DmSummary,
  MessagingClient,
} from "../messaging/types.js";

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
    throw err;
  }
  return { client, token };
};

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
    let client: MessagingClient | undefined;
    try {
      const resolved = await resolveClient(json);
      client = resolved.client;
      const conversations = await listConversations(client, {
        token: resolved.token,
        onProfileProgress: progress.update,
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
      if (client) await client.close();
    }
  });

dmCommand
  .command("requests")
  .description("List inbound message requests (pending your approval)")
  .action(async function (this: Command) {
    const json = getJson(this);
    const progress = startInboxProgress(json);
    let client: MessagingClient | undefined;
    try {
      const resolved = await resolveClient(json);
      client = resolved.client;
      const requests = await listRequests(client, {
        token: resolved.token,
        onProfileProgress: progress.update,
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
      if (client) await client.close();
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
    const { client, token } = await resolveClient(json);
    try {
      const { profile, messages } = await readConversation(client, peer, {
        token,
        limit,
      });
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
    } finally {
      await client.close();
    }
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
    const { client, token } = await resolveClient(json);
    try {
      const sent = await sendReply(client, peer, message, { token });
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
      if (err instanceof NewConversationDeniedError) {
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
    } finally {
      await client.close();
    }
  });

dmCommand
  .command("listen")
  .description(
    "Stream incoming DMs in real time (no polling — uses XMTP's server-push stream to avoid rate limits)",
  )
  .action(async function (this: Command) {
    const json = getJson(this);
    const { client } = await resolveClient(json);

    if (!json) {
      console.log("Listening for new DMs… (Ctrl+C to stop)\n");
    }

    const shutdown = () => {
      client.close().finally(() => process.exit(0));
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);

    // Cache resolved peer labels to avoid a UAPI call per message.
    const labelCache = new Map<string, string>();
    const cachedPeerLabel = async (peer: Address): Promise<string> => {
      const cached = labelCache.get(peer);
      if (cached) return cached;
      const label = await peerLabel(peer);
      labelCache.set(peer, label);
      return label;
    };

    let messageCount = 0;

    track("cli_dm_listen_start", {
      output_format: json ? "json" : "text",
    });

    try {
      for await (const msg of client.streamAllMessages()) {
        if (msg.fromSelf) continue;

        messageCount++;

        const who = msg.peerAddress
          ? await cachedPeerLabel(msg.peerAddress)
          : "unknown";

        if (json) {
          console.log(
            JSON.stringify({
              from: who,
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
          console.log(`← ${who} ${dim(formatAge(msg.sentAtMs))}\n  ${first}`);
          for (const line of rest) console.log(`  ${line}`);
        }
      }
    } finally {
      track("cli_dm_listen_end", {
        output_format: json ? "json" : "text",
        message_count: messageCount,
      });
      await client.close();
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
      const { client } = await resolveClient(json);
      try {
        await setConsentForPeer(client, peer, consent);
        const label = await peerLabel(peer);
        outputData(json, {
          json: { address: peer, consent },
          render: () =>
            console.log(
              `Added ${label} to DM ${name === "approve" ? "allowlist" : "denylist"}`,
            ),
        });
        track(`cli_dm_${name}`, { output_format: json ? "json" : "text" });
      } finally {
        await client.close();
      }
    });
};

consentSubcommand("approve", "allowed", "Approve an inbound request");
consentSubcommand("deny", "denied", "Deny an inbound request");
