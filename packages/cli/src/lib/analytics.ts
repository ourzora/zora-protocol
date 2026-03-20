import { PostHog } from "posthog-node";
import { createHash, randomUUID } from "node:crypto";
import { privateKeyToAccount } from "viem/accounts";
import {
  getAnalyticsId,
  getApiKey,
  getPrivateKey,
  saveAnalyticsId,
} from "./config.js";
import { POSTHOG_HOST, POSTHOG_TOKEN } from "./constants.js";
import { normalizeKey } from "./wallet.js";
const SHUTDOWN_TIMEOUT_MS = 2000;

declare const PKG_VERSION: string | undefined;

let client: PostHog | null = null;
let distinctId: string | null = null;

const isDisabled = (): boolean =>
  process.env.ZORA_NO_ANALYTICS === "1" ||
  process.env.DO_NOT_TRACK === "1" ||
  process.env.CI !== undefined ||
  process.env.NODE_ENV === "test";

const getOrCreateDistinctId = (): string => {
  if (distinctId) return distinctId;

  try {
    const stored = getAnalyticsId();
    if (stored) {
      distinctId = stored;
      return distinctId;
    }

    distinctId = randomUUID();
    saveAnalyticsId(distinctId);
    return distinctId;
  } catch {
    distinctId = randomUUID();
    return distinctId;
  }
};

const getClient = (): PostHog => {
  if (!client) {
    client = new PostHog(POSTHOG_TOKEN, { host: POSTHOG_HOST });
  }
  return client;
};

const commonProperties = (): Record<string, unknown> => ({
  cli_version: typeof PKG_VERSION !== "undefined" ? PKG_VERSION : "development",
  os: process.platform,
  arch: process.arch,
  node_version: process.version,
});

const hashApiKey = (key: string): string =>
  createHash("sha256").update(key).digest("hex").slice(0, 16);

const getWalletAddress = (): string | undefined => {
  try {
    const key = process.env.ZORA_PRIVATE_KEY || getPrivateKey();
    if (!key) return undefined;

    return privateKeyToAccount(normalizeKey(key)).address;
  } catch {
    return undefined;
  }
};

let identified = false;

export const identify = (): void => {
  try {
    if (isDisabled() || identified) return;
    identified = true;

    const id = getOrCreateDistinctId();
    const apiKey = getApiKey();
    const walletAddress = getWalletAddress();

    if (!apiKey && !walletAddress) {
      return;
    }

    getClient().identify({
      distinctId: id,
      properties: {
        api_key_hash: apiKey ? hashApiKey(apiKey) : undefined,
        wallet_address: walletAddress ?? undefined,
      },
    });
  } catch {
    // Analytics should never break the CLI
  }
};

export const track = (
  event: string,
  properties?: Record<string, unknown>,
): void => {
  try {
    if (isDisabled()) return;

    getClient().capture({
      distinctId: getOrCreateDistinctId(),
      event,
      properties: { ...commonProperties(), ...properties },
    });
  } catch {
    // Analytics should never break the CLI
  }
};

export const shutdownAnalytics = async (): Promise<void> => {
  if (!client) return;

  const flushing = client;
  client = null;

  try {
    await Promise.race([
      flushing.shutdown(),
      new Promise((resolve) => setTimeout(resolve, SHUTDOWN_TIMEOUT_MS)),
    ]);
  } catch {
    // Swallow shutdown errors
  }
};
