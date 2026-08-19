import {
  getPrivateKey,
  getSmartWalletAddress,
  getDmCheckAt,
  saveDmCheckAt,
} from "../lib/config.js";
import { normalizeKey } from "../lib/wallet.js";
import { createCliSmartWalletProvider } from "./cli-auth-provider.js";
import { createSmartWalletAuth } from "./identity.js";
import type { DmSummary } from "./types.js";

/** Don't sync more than once per this interval, per machine. */
const THROTTLE_MS = 10 * 60 * 1000;

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;
const note = (msg: string) => process.stderr.write(`\n\x1b[2m${msg}\x1b[0m\n`);

/**
 * Best-effort "you have new DMs" notice, printed (to stderr) after a non-dm
 * command. Throttled to at most once per {@link THROTTLE_MS} per machine via a
 * timestamp in the local config — "new" is measured against the previous check.
 *
 * Loads the XMTP client only when it actually runs (past the throttle + guards),
 * so it never adds the native binding or auth to commands that don't need them,
 * and every failure is swallowed so it can never disrupt the primary command.
 *
 * Set `ZORA_DM_NOTIFY=always` to bypass the throttle and surface why it's quiet
 * (no smart wallet, nothing new, or an error) — useful for verifying the check.
 */
export async function maybeNotifyNewDms(): Promise<void> {
  const force = process.env.ZORA_DM_NOTIFY === "always";
  try {
    // Only when DMs are set up — keep this entirely off the path for everyone else.
    if (!getSmartWalletAddress()) {
      if (force)
        note("📭 DM check skipped: no smart wallet — run `zora agent create`.");
      return;
    }
    const key = process.env.ZORA_PRIVATE_KEY || getPrivateKey();
    if (!key) {
      if (force) note("📭 DM check skipped: no wallet configured.");
      return;
    }

    const now = Date.now();
    const lastCheckAt = getDmCheckAt();
    if (!force && lastCheckAt && now - lastCheckAt < THROTTLE_MS) return;

    // Claim the throttle window up front so a slow or failing check doesn't
    // repeat on the next command. A fresh machine (no prior check) reports
    // nothing — it just records the baseline; only activity after that is "new".
    // Force mode leaves the real throttle/baseline untouched so it's a pure read-out.
    if (!force) saveDmCheckAt(now);
    const baseline = lastCheckAt;

    const provider = await createCliSmartWalletProvider({
      privateKey: normalizeKey(key),
    });
    const auth = createSmartWalletAuth(provider);
    const { createMessagingClient } = await import("./client.js");
    const client = await createMessagingClient(auth.signerSpec);

    try {
      await client.sync(["unknown"]);
      const requests = await client.listDms(["unknown"]);
      await client.sync(["allowed"]);
      const active = await client.listDms(["allowed"]);

      // Only surface what arrived since the last check. With no prior baseline
      // (first run) nothing is "new" — we just record the baseline and stay quiet.
      const newSince = (summaries: DmSummary[]) =>
        baseline
          ? summaries.filter(
              (c) =>
                c.lastMessage &&
                !c.lastMessage.fromSelf &&
                c.lastMessage.sentAtMs > baseline,
            ).length
          : 0;

      const newRequests = newSince(requests);
      const newMessages = newSince(active);

      const lines: string[] = [];
      if (newRequests > 0) {
        lines.push(
          `📨 ${plural(newRequests, "new message request")} — run \`zora dm requests\``,
        );
      }
      if (newMessages > 0) {
        lines.push(
          `💬 new messages in ${plural(newMessages, "conversation")} — run \`zora dm list\``,
        );
      }
      if (lines.length > 0) {
        note(lines.join("\n"));
      } else if (force) {
        note("📭 No new DMs or message requests.");
      }
    } finally {
      await client.close();
    }
  } catch (err) {
    // Best-effort — never disrupt the primary command.
    if (force) note(`📭 DM check failed: ${(err as Error).message}`);
  }
}
