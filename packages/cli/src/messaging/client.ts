import { homedir, platform } from "node:os";
import { join } from "node:path";
import { mkdirSync } from "node:fs";
import type {
  ConsentState,
  Dm,
  DecodedMessage,
  Identifier,
  Signer,
  XmtpEnv,
} from "@xmtp/node-sdk";
import { ReactionCodec } from "@xmtp/content-type-reaction";
import { ReadReceiptCodec } from "@xmtp/content-type-read-receipt";
import { getAddress, type Address } from "viem";
import { loadXmtpSdk } from "./load-xmtp-sdk.js";
import type { XmtpSignerSpec } from "./identity.js";
import type {
  DmConsent,
  DmMessage,
  DmSummary,
  MessagingClient,
} from "./types.js";

/**
 * The single module that touches the `@xmtp/node-sdk` runtime (and its native
 * binding). Everything else in `messaging/` depends only on the node-sdk-free
 * `MessagingClient` interface, so the rest of the feature — and its tests — does
 * not load the native binding. This adapter maps node-sdk `Dm`/`DecodedMessage`
 * into the plain shapes in `types.ts`.
 *
 * The SDK is loaded at runtime via {@link loadXmtpSdk} so the right native
 * binding is picked for this platform's libc (see load-xmtp-sdk.ts). Only types
 * are imported statically here — those are erased at build time and never touch
 * the binding. The enum-backed helpers therefore live inside
 * {@link createMessagingClient}, where the runtime SDK is available.
 */

const formatContentType = (ct: {
  authorityId: string;
  typeId: string;
  versionMajor: number;
  versionMinor: number;
}): string =>
  `${ct.authorityId}/${ct.typeId}:${ct.versionMajor}.${ct.versionMinor}`;

/** Returns a viem-checksummed Address, or null if the string isn't an address. */
const asAddress = (value: string | undefined): Address | null => {
  if (!value) return null;
  try {
    return getAddress(value);
  } catch {
    return null;
  }
};

/** Path of the local XMTP SQLite store, under the CLI's config dir. */
const defaultDbPath = (env: XmtpEnv, inboxId: string): string => {
  const base =
    platform() === "win32"
      ? join(
          process.env.APPDATA ?? join(homedir(), "AppData", "Roaming"),
          "zora",
        )
      : join(homedir(), ".config", "zora");
  const dir = join(base, "xmtp");
  mkdirSync(dir, { recursive: true });
  return join(dir, `xmtp-${env}-${inboxId}.db3`);
};

export interface CreateMessagingClientOptions {
  env?: XmtpEnv;
  /** 32-byte hex/bytes key encrypting the local DB at rest. */
  dbEncryptionKey?: Uint8Array | `0x${string}`;
  /** Override the local DB path (defaults under ~/.config/zora/xmtp). */
  dbPath?: string;
  /**
   * Optional hook invoked once with the XMTP installation id after the client is
   * created, used to register the installation with the Zora backend. Best-effort:
   * failures are swallowed so DM operations still work if registration fails.
   */
  registerInstallation?: (installationId: string) => Promise<void>;
}

/**
 * Creates an XMTP client for the given identity and returns a `MessagingClient`
 * adapter. On first run this proves control of the inbox (one signature via the
 * auth layer) and registers a new installation; later runs reuse the local DB.
 */
export const createMessagingClient = async (
  spec: XmtpSignerSpec,
  options: CreateMessagingClientOptions = {},
): Promise<MessagingClient> => {
  // Load the SDK whose native binding can load on this platform's libc. This is
  // the call that actually pulls in the native binding, so a glibc-too-old /
  // missing-binary failure surfaces here and is caught by the dm command.
  const { Client, ConsentState, IdentifierKind, LogLevel, isText } =
    await loadXmtpSdk();

  // Enum-backed helpers — defined here because the enums are runtime values from
  // the dynamically loaded SDK (only their types are imported statically above).
  const consentToSdk: Record<DmConsent, ConsentState> = {
    allowed: ConsentState.Allowed,
    unknown: ConsentState.Unknown,
    denied: ConsentState.Denied,
  };
  const consentFromSdk = (state: ConsentState): DmConsent => {
    if (state === ConsentState.Allowed) return "allowed";
    if (state === ConsentState.Denied) return "denied";
    return "unknown";
  };
  const toIdentifier = (address: Address): Identifier => ({
    identifier: address.toLowerCase(),
    identifierKind: IdentifierKind.Ethereum,
  });
  const buildXmtpSigner = (s: XmtpSignerSpec): Signer => {
    const getIdentifier = () => toIdentifier(s.address);
    if (s.type === "EOA") {
      return { type: "EOA", getIdentifier, signMessage: s.signMessage };
    }
    return {
      type: "SCW",
      getIdentifier,
      getChainId: () => BigInt(s.chainId),
      signMessage: s.signMessage,
    };
  };

  const env: XmtpEnv = options.env ?? "production";
  const signer = buildXmtpSigner(spec);

  // Assigned to a variable (not an inline literal) so TS width-subtyping allows
  // network options like `env`/`appVersion`, which node-sdk's
  // `Omit<ClientOptions, "codecs">` param type drops when it collapses the
  // NetworkOptions union.
  const clientOptions = {
    env,
    appVersion: "zora/cli",
    codecs: [new ReactionCodec(), new ReadReceiptCodec()],
    dbEncryptionKey: options.dbEncryptionKey,
    dbPath:
      options.dbPath ?? ((inboxId: string) => defaultDbPath(env, inboxId)),
    loggingLevel: LogLevel.Off,
  };

  const client = await Client.create(signer, clientOptions);

  if (options.registerInstallation) {
    // Best-effort: registration is push/device-list bookkeeping and must never
    // block reading or sending DMs.
    try {
      await options.registerInstallation(client.installationId);
    } catch {
      // ignored — see doc comment on registerInstallation
    }
  }

  const address = getAddress(spec.address);
  const selfInboxId = client.inboxId;

  const addressMapForDm = async (dm: Dm): Promise<Map<string, Address>> => {
    const members = await dm.members();
    const map = new Map<string, Address>();
    for (const member of members) {
      const addr = asAddress(member.accountIdentifiers[0]?.identifier);
      if (addr) map.set(member.inboxId, addr);
    }
    return map;
  };

  const toMessage = (
    message: DecodedMessage,
    addrByInbox: Map<string, Address>,
  ): DmMessage => ({
    id: message.id,
    senderAddress: addrByInbox.get(message.senderInboxId) ?? null,
    fromSelf: message.senderInboxId === selfInboxId,
    text: isText(message) ? (message.content ?? null) : null,
    contentType: formatContentType(message.contentType),
    sentAtMs: Number(message.sentAtNs / 1_000_000n),
  });

  const findDm = (peerAddress: Address): Promise<Dm | undefined> =>
    client.conversations.fetchDmByIdentifier(toIdentifier(peerAddress));

  /** Active stream abort controller, if any. */
  let streamAbort: AbortController | undefined;

  return {
    address,

    async sync(consent?: DmConsent[]): Promise<void> {
      const states = consent?.map((c) => consentToSdk[c]);
      await client.conversations.syncAll(states);
      await client.conversations.sync();
    },

    async listDms(consent?: DmConsent[]): Promise<DmSummary[]> {
      const states = consent?.map((c) => consentToSdk[c]);
      const dms = client.conversations.listDms({ consentStates: states });
      return Promise.all(
        dms.map(async (dm): Promise<DmSummary> => {
          const [addrByInbox, lastMessage] = await Promise.all([
            addressMapForDm(dm),
            dm.lastMessage(),
          ]);
          return {
            id: dm.id,
            peerAddress: addrByInbox.get(dm.peerInboxId) ?? null,
            consent: consentFromSdk(dm.consentState()),
            profile: null,
            lastMessage: lastMessage
              ? toMessage(lastMessage, addrByInbox)
              : null,
          };
        }),
      );
    },

    async readMessages(peerAddress: Address, limit = 30): Promise<DmMessage[]> {
      const dm = await findDm(peerAddress);
      if (!dm) return [];
      const [addrByInbox, messages] = await Promise.all([
        addressMapForDm(dm),
        dm.messages({ limit }),
      ]);
      return messages.map((m) => toMessage(m, addrByInbox));
    },

    async sendText(
      peerAddress: Address,
      text: string,
      gateNewConversation?: (peerAddress: Address) => Promise<void>,
    ): Promise<DmMessage> {
      let dm = await findDm(peerAddress);
      if (!dm) {
        if (gateNewConversation) await gateNewConversation(peerAddress);
        dm = await client.conversations.createDmWithIdentifier(
          toIdentifier(peerAddress),
        );
      }
      const id = await dm.sendText(text);
      return {
        id,
        senderAddress: address,
        fromSelf: true,
        text,
        contentType: "xmtp.org/text:1.0",
        sentAtMs: Date.now(),
      };
    },

    async setConsent(peerAddress: Address, consent: DmConsent): Promise<void> {
      const dm = await findDm(peerAddress);
      if (!dm) {
        throw new Error(`No conversation found with ${peerAddress}`);
      }
      // Must await: updateConsentState writes to SQLite via the native binding,
      // and the short-lived CLI exits right after, abandoning an un-awaited write.
      await dm.updateConsentState(consentToSdk[consent]);
    },

    streamAllMessages(): AsyncIterable<
      DmMessage & { peerAddress: Address | null }
    > {
      // Initial sync so we don't miss anything that arrived while offline.
      // The stream itself is a gRPC server-push — no polling, ≈ zero reads at
      // rest — which avoids the 20 000-read / 5-min XMTP rate limit that
      // repeated sync+listDms polling hits.
      const ctrl = new AbortController();
      streamAbort = ctrl;

      const outerClient = client;

      async function* generate() {
        // One-time catch-up sync before opening the stream.
        await outerClient.conversations.sync();

        const stream = await outerClient.conversations.streamAllMessages();

        for await (const message of stream) {
          if (ctrl.signal.aborted) break;

          // Look up the conversation for this message. If it's a brand-new
          // sender the local store hasn't seen yet, re-sync conversations so
          // the first message isn't silently dropped.
          let convo = outerClient.conversations
            .listDms()
            .find((dm) => dm.id === message.conversationId);
          if (!convo) {
            await outerClient.conversations.sync();
            convo = outerClient.conversations
              .listDms()
              .find((dm) => dm.id === message.conversationId);
            if (!convo) continue; // truly not a DM (e.g. group message)
          }

          const addrByInbox = await addressMapForDm(convo);
          const dmMessage = toMessage(message, addrByInbox);
          const peerAddr = addrByInbox.get(convo.peerInboxId) ?? null;
          yield { ...dmMessage, peerAddress: peerAddr };
        }
      }

      return generate();
    },

    async close(): Promise<void> {
      // Abort any active stream.
      if (streamAbort) {
        streamAbort.abort();
        streamAbort = undefined;
      }
      // node-sdk v6 exposes no explicit client close; the CLI is short-lived and
      // the SQLite connection is released on process exit. Kept for interface
      // symmetry and future-proofing.
    },
  };
};
