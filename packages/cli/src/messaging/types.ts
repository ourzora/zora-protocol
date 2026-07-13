import type { Address } from "viem";

/**
 * Plain, node-sdk-free data shapes for the DM feature. The XMTP `node-sdk` (and
 * its native binding) is confined to `client.ts`; everything else — core logic,
 * commands, tests — speaks these types. This keeps the bulk of the feature
 * decoupled from the SDK, gives stable `--json` output shapes, and lets the unit
 * suite run without loading the native binding.
 */

/** Consent state of a conversation, mirroring XMTP `ConsentState` without importing it. */
export type DmConsent = "allowed" | "unknown" | "denied";

/** A resolved Zora profile for a conversation counterpart (from UAPI `profiles`). */
export interface MessagingProfile {
  address: Address;
  handle: string | null;
  displayName: string | null;
  avatarUrl: string | null;
  /** True if this profile has been blocked by the platform (ToS violation, etc.). */
  platformBlocked: boolean;
}

/** A single decrypted DM message. */
export interface DmMessage {
  id: string;
  /** Address of the sender, or null when it can't be resolved to a member. */
  senderAddress: Address | null;
  /** True when the message was sent by the local inbox. */
  fromSelf: boolean;
  /** Plain text content; null for non-text content types (reactions, cards, …). */
  text: string | null;
  /** Content-type id (e.g. `xmtp.org/text:1.0`) for non-text messages. */
  contentType: string;
  /** Unix milliseconds the message was sent. */
  sentAtMs: number;
}

/** An XMTP installation (device) registered to the inbox. */
export interface InstallationInfo {
  /** Installation id (hex). */
  id: string;
  /** When the installation was registered (epoch ms), when the network reports it. */
  createdAtMs?: number;
  /** True for the installation this client is currently running as. */
  current: boolean;
}

/** A DM conversation summary for `zora dm list` / `zora dm requests`. */
export interface DmSummary {
  /** XMTP conversation id. */
  id: string;
  /** Counterpart member address, when resolvable. */
  peerAddress: Address | null;
  consent: DmConsent;
  /** Resolved Zora profile for the peer, when available. */
  profile: MessagingProfile | null;
  /** Preview of the most recent message, when present. */
  lastMessage: DmMessage | null;
}

/**
 * The narrow XMTP surface the core logic depends on. `client.ts` provides the
 * concrete implementation over `@xmtp/node-sdk`; tests provide a fake. Methods
 * deal only in the plain types above.
 */
export interface MessagingClient {
  /** Address that owns this inbox (SCW in prod, EOA in dev). */
  readonly address: Address;
  /** Pull new envelopes from the network into the local store and decrypt. */
  sync(consent?: DmConsent[]): Promise<void>;
  /** List DM conversations, optionally filtered by consent state. */
  listDms(consent?: DmConsent[]): Promise<DmSummary[]>;
  /** Read message history for the DM with `peerAddress`, newest first. */
  readMessages(peerAddress: Address, limit?: number): Promise<DmMessage[]>;
  /**
   * Send `text` to `peerAddress`, creating the DM if needed. `gateNewConversation`
   * is invoked before creating a brand-new conversation and may reject the send.
   */
  sendText(
    peerAddress: Address,
    text: string,
    gateNewConversation?: (peerAddress: Address) => Promise<void>,
  ): Promise<DmMessage>;
  /** Update the consent state of the DM with `peerAddress`. */
  setConsent(peerAddress: Address, consent: DmConsent): Promise<void>;
  /**
   * Stream all incoming DM messages in real time via a long-lived connection.
   * Returns an `AsyncIterable` that yields `DmMessage` objects as they arrive.
   * Callers must call `close()` when done to tear down the stream.
   *
   * Prefer this over polling `sync()` + `listDms()` to avoid XMTP read rate
   * limits (20 000 reads / 5 min). The stream makes ≈ zero requests at rest.
   *
   * Each yielded message carries the `consent` state of its conversation so
   * callers can tell an allowed DM from an `unknown`-consent message request
   * (a first message from a stranger, pending approval) without a second lookup.
   */
  streamAllMessages(): AsyncIterable<
    DmMessage & { peerAddress: Address | null; consent: DmConsent }
  >;
  /**
   * List the XMTP installations (devices) registered to this inbox, from the
   * network — so an agent can see and manage its own devices against the
   * 10-installation-per-inbox cap without leaving the CLI.
   */
  listInstallations(): Promise<InstallationInfo[]>;
  /**
   * Revoke installations by id, freeing slots against the cap. Unknown ids are
   * ignored. The caller is responsible for not revoking the current device.
   */
  revokeInstallations(ids: string[]): Promise<void>;
  /** Revoke every installation except the one this client is running as. */
  revokeOtherInstallations(): Promise<void>;
  /** Close the underlying SDK database connection and any active streams. */
  close(): Promise<void>;
}
