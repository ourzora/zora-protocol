import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  chmodSync,
} from "node:fs";
import { join } from "node:path";
import { formatError } from "./errors.js";
import { safeExit, ERROR } from "./exit.js";
import { homedir, platform } from "node:os";
import { Address, isAddress } from "viem";

function getConfigDir(): string {
  if (platform() === "win32") {
    return join(
      process.env.APPDATA ?? join(homedir(), "AppData", "Roaming"),
      "zora",
    );
  }
  return join(homedir(), ".config", "zora");
}

const CONFIG_DIR = getConfigDir();
const CONFIG_FILE = join(CONFIG_DIR, "config.json");

const WALLET_FILE = join(CONFIG_DIR, "wallet.json");

const CONFIG_VERSION = 1;
const WALLET_VERSION = 1;

const PRIVATE_KEY_REGEX = /(^|\b)(0x)?[0-9a-fA-F]{64}(\b|$)/;

interface Config {
  version: number;
  apiKey?: string;
  analyticsId?: string;
  /** Epoch ms of the last background DM check (throttles the new-DM notice). */
  dmCheckAt?: number;
}

/**
 * The full identity of an agent created by `zora agent create`. Persisted under
 * the `agent` key of the wallet file; its presence marks the wallet as
 * agent-owned (see {@link isAgentWallet}).
 */
export interface AgentWalletInfo {
  /** EOA address derived from the wallet `privateKey` — the agent's owner key. */
  address: Address;
  /** Privy embedded wallet address provisioned during onboarding. */
  embeddedWalletAddress: Address;
  /** Smart wallet (account) address that holds the agent's coins and posts. */
  smartWalletAddress: Address;
  /** Privy DID for the agent's account. */
  did: string;
  /** Zora profile handle (without the leading `@`). */
  username: string;
  /** Public Zora profile URL. */
  profileUrl: string;
  /** ISO-8601 timestamp recorded when the agent was created. */
  createdAt: string;
}

interface Wallet {
  version: number;
  privateKey: string;
  smartWalletAddress?: Address;
  /** Present when this wallet was created by `zora agent create`. */
  agent?: AgentWalletInfo;
}

function assertVersion(
  parsed: unknown,
  expectedVersion: number,
  filePath: string,
): void {
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error(`${filePath}: expected an object`);
  }
  const obj = parsed as Record<string, unknown>;
  if (!("version" in obj)) {
    throw new Error(`${filePath}: missing required field "version"`);
  }
  if (obj.version !== expectedVersion) {
    throw new Error(
      `${filePath}: unsupported version ${obj.version} (expected ${expectedVersion})`,
    );
  }
}

let configReadOnly = false;

function readConfig(): Config {
  if (!existsSync(CONFIG_FILE)) return { version: CONFIG_VERSION };
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
  } catch (err) {
    console.error(
      `Warning: could not parse ${CONFIG_FILE}: ${formatError(err)}. Run 'zora auth configure' to fix.`,
    );
    configReadOnly = true;
    return { version: CONFIG_VERSION };
  }
  try {
    assertVersion(parsed, CONFIG_VERSION, CONFIG_FILE);
  } catch (err) {
    console.error(
      `Warning: ${formatError(err)}. Delete ${CONFIG_FILE} or run 'zora auth configure' to reset.`,
    );
    configReadOnly = true;
    return { version: CONFIG_VERSION };
  }
  return parsed as Config;
}

const IS_WINDOWS = platform() === "win32";

function writeSecure(filePath: string, data: string): void {
  writeFileSync(filePath, data, IS_WINDOWS ? {} : { mode: 0o600 });
  if (!IS_WINDOWS) {
    chmodSync(filePath, 0o600);
  }
}

function writeConfig(config: Config): void {
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeSecure(
    CONFIG_FILE,
    JSON.stringify({ ...config, version: CONFIG_VERSION }, null, 2) + "\n",
  );
}

function readWallet(): Wallet | undefined {
  if (!existsSync(WALLET_FILE)) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(WALLET_FILE, "utf-8"));
  } catch (err) {
    throw new Error(`${WALLET_FILE}: ${(err as Error).message}`);
  }
  assertVersion(parsed, WALLET_VERSION, WALLET_FILE);
  const obj = parsed as Record<string, unknown>;
  if (typeof obj.privateKey !== "string" || !obj.privateKey) {
    throw new Error(`${WALLET_FILE}: missing or invalid "privateKey" field`);
  }
  if (
    obj.smartWalletAddress &&
    (typeof obj.smartWalletAddress !== "string" ||
      !isAddress(obj.smartWalletAddress))
  ) {
    throw new Error(`${WALLET_FILE}: invalid "smartWalletAddress" field`);
  }
  if (obj.agent !== undefined) {
    assertValidAgentInfo(obj.agent, WALLET_FILE);
  }
  return parsed as Wallet;
}

function assertValidAgentInfo(value: unknown, filePath: string): void {
  if (typeof value !== "object" || value === null) {
    throw new Error(`${filePath}: invalid "agent" field — expected an object`);
  }
  const agent = value as Record<string, unknown>;
  for (const field of [
    "address",
    "embeddedWalletAddress",
    "smartWalletAddress",
  ] as const) {
    const addr = agent[field];
    if (typeof addr !== "string" || !isAddress(addr)) {
      throw new Error(`${filePath}: invalid "agent.${field}" field`);
    }
  }
  for (const field of ["did", "username", "profileUrl", "createdAt"] as const) {
    if (typeof agent[field] !== "string" || !agent[field]) {
      throw new Error(`${filePath}: missing or invalid "agent.${field}" field`);
    }
  }
}

function writeWallet(wallet: Partial<Omit<Wallet, "version">>): void {
  mkdirSync(CONFIG_DIR, { recursive: true });
  let currentWalletRaw: string | undefined;
  let currentWallet: Wallet | undefined;
  if (existsSync(WALLET_FILE)) {
    // to enable partial updates, we read the current wallet file and merge the new wallet data with it
    // we specifically *don't* use readWallet() here to avoid any validation checks from throwing errors
    // (this allows us to override corrupted entries)
    try {
      currentWalletRaw = readFileSync(WALLET_FILE, "utf-8");
      currentWallet = JSON.parse(currentWalletRaw) as Wallet;
    } catch (err) {
      // if we fail to parse the contents, we warn the user and try to create a new wallet file
      console.warn(
        `Warning: Malformed wallet file ${WALLET_FILE}: ${formatError(err)}.`,
      );
      console.info(`Attempting to recover by creating a new wallet file.`);
      // try to extract the private key from the current wallet file (so we don't lose it during the recovery process)
      // if it's already corrupted, there's nothing we can do...
      const privateKey = currentWalletRaw?.match(PRIVATE_KEY_REGEX)?.[0];
      if (privateKey) {
        currentWallet = { privateKey, version: WALLET_VERSION };
      }
    }
  }
  writeSecure(
    WALLET_FILE,
    JSON.stringify(
      { ...currentWallet, ...wallet, version: WALLET_VERSION },
      null,
      2,
    ) + "\n",
  );
}

/** Returns the env-var key if set (errors on empty), or undefined if unset. */
export function getEnvApiKey(): string | undefined {
  const envKey = process.env.ZORA_API_KEY;
  if (envKey === undefined) return undefined;
  if (!envKey) {
    console.error(
      "ZORA_API_KEY is set but empty. Provide a valid key or unset the variable.",
    );
    safeExit(ERROR);
  }
  return envKey;
}

export function getApiKey(): string | undefined {
  return getEnvApiKey() ?? readConfig().apiKey;
}

export function saveApiKey(apiKey: string): void {
  const config = readConfig();
  config.apiKey = apiKey;
  writeConfig(config);
}

export function getPrivateKey(): string | undefined {
  return readWallet()?.privateKey;
}

export function savePrivateKey(privateKey: string): void {
  writeWallet({ privateKey });
}

export function getSmartWalletAddress(): Address | undefined {
  return readWallet()?.smartWalletAddress;
}

export function saveSmartWalletAddress(smartWalletAddress: Address): void {
  writeWallet({ smartWalletAddress });
}

/** Returns the agent identity if this wallet was created by `zora agent create`. */
export function getAgentWallet(): AgentWalletInfo | undefined {
  return readWallet()?.agent;
}

/** True when the wallet file records an agent identity. */
export function isAgentWallet(): boolean {
  return getAgentWallet() !== undefined;
}

/**
 * Persist the full identity created by `zora agent create`. Records the agent
 * metadata under the `agent` key and mirrors the smart wallet address to the
 * top-level field so the trading commands resolve it automatically (see
 * {@link getSmartWalletAddress}). Merges into any existing wallet file, leaving
 * the stored private key untouched.
 */
export function saveAgentWallet(agent: AgentWalletInfo): void {
  writeWallet({ smartWalletAddress: agent.smartWalletAddress, agent });
}

export function getWalletPath(): string {
  return WALLET_FILE;
}

export function getAnalyticsId(): string | undefined {
  return readConfig().analyticsId;
}

export function saveAnalyticsId(id: string): void {
  if (configReadOnly) return;
  const config = readConfig();
  config.analyticsId = id;
  writeConfig(config);
}

export function getDmCheckAt(): number | undefined {
  return readConfig().dmCheckAt;
}

export function saveDmCheckAt(ms: number): void {
  if (configReadOnly) return;
  const config = readConfig();
  config.dmCheckAt = ms;
  writeConfig(config);
}

export function getConfigPath(): string {
  return CONFIG_FILE;
}
