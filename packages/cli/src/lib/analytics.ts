import { createHash, randomUUID } from "node:crypto";
import { PostHog } from "posthog-node";
import { Address, privateKeyToAccount } from "viem/accounts";
import {
  resolvePrivateKey,
  resolveSmartWalletAddress,
} from "./account/index.js";
import { getAnalyticsId, getApiKey, saveAnalyticsId } from "./config.js";
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

const getWalletAddresses = () => {
  const addresses = {
    wallet: undefined as Address | undefined,
    smartWallet: undefined as Address | undefined,
  };
  try {
    const privateKey = resolvePrivateKey();
    addresses.wallet = privateKeyToAccount(normalizeKey(privateKey)).address;
  } catch {
    addresses.wallet = undefined;
  }
  try {
    const smartWalletAddress = resolveSmartWalletAddress();
    addresses.smartWallet = smartWalletAddress;
  } catch {
    addresses.smartWallet = undefined;
  }
  return addresses;
};

const commonProperties = (): Record<string, unknown> => {
  const addresses = getWalletAddresses();
  return {
    cli_version:
      typeof PKG_VERSION !== "undefined" ? PKG_VERSION : "development",
    os: process.platform,
    arch: process.arch,
    node_version: process.version,
    wallet_address: addresses.wallet,
    smart_wallet_address: addresses.smartWallet,
  };
};

const hashApiKey = (key: string): string =>
  createHash("sha256").update(key).digest("hex").slice(0, 16);

let identified = false;

export const identify = (): void => {
  try {
    if (isDisabled() || identified) return;
    identified = true;

    const id = getOrCreateDistinctId();
    const apiKey = getApiKey();
    const { wallet: walletAddress, smartWallet: smartWalletAddress } =
      getWalletAddresses();

    if (!apiKey && !walletAddress && !smartWalletAddress) {
      return;
    }

    getClient().identify({
      distinctId: id,
      properties: {
        api_key_hash: apiKey ? hashApiKey(apiKey) : undefined,
        wallet_address: walletAddress ?? undefined,
        smart_wallet_address: smartWalletAddress ?? undefined,
      },
    });
  } catch {
    // Analytics should never break the CLI
  }
};

/**
 * Set properties on the PostHog person (profile) tied to this install.
 *
 * Unlike event properties (which describe a single action), person properties
 * persist on the user across events — e.g. their agent username or email.
 * posthog-node sends these as `$set`, so later calls overwrite earlier values.
 * Pass only the keys to set; undefined/empty values are skipped.
 */
export const setPersonProperties = (
  properties: Record<string, unknown>,
): void => {
  try {
    if (isDisabled()) return;

    const cleaned = Object.fromEntries(
      Object.entries(properties).filter(
        ([, value]) => value !== undefined && value !== null && value !== "",
      ),
    );
    if (Object.keys(cleaned).length === 0) return;

    getClient().identify({
      distinctId: getOrCreateDistinctId(),
      properties: cleaned,
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
