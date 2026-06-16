import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  chmodSync,
  rmSync,
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

const SESSION_FILE = join(CONFIG_DIR, "session.json");

const BUDGET_FILE = join(CONFIG_DIR, "budget.json");

const CONFIG_VERSION = 1;
const WALLET_VERSION = 1;
const SESSION_VERSION = 1;
const BUDGET_VERSION = 1;

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

/**
 * Reads and parses the wallet file WITHOUT the strict validation `readWallet`
 * applies, returning `undefined` on any problem instead of throwing. Used by the
 * destructive-action guards so they can still detect an agent even when the
 * wallet file is otherwise malformed (e.g. a corrupt key).
 */
function peekWalletFile(): Record<string, unknown> | undefined {
  if (!existsSync(WALLET_FILE)) return undefined;
  try {
    const parsed: unknown = JSON.parse(readFileSync(WALLET_FILE, "utf-8"));
    return typeof parsed === "object" && parsed !== null
      ? (parsed as Record<string, unknown>)
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Returns the recorded agent identity if one is present, reading defensively so
 * a malformed wallet file never throws (unlike {@link getAgentWallet}). Guards
 * that protect an agent setup use this so they fire even on a partially-corrupt
 * file; it shape-checks only the fields those guards display.
 */
export function peekAgentWallet(): AgentWalletInfo | undefined {
  const agent = peekWalletFile()?.agent as AgentWalletInfo | undefined;
  if (
    agent &&
    typeof agent === "object" &&
    typeof agent.username === "string" &&
    typeof agent.smartWalletAddress === "string" &&
    typeof agent.address === "string"
  ) {
    return agent;
  }
  return undefined;
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

const stripKeyPrefix = (key: string): string =>
  key.trim().toLowerCase().replace(/^0x/, "");

export function savePrivateKey(privateKey: string): void {
  // If the wallet records an agent identity and the key is actually changing,
  // that identity no longer applies — the recorded agent was owned by the OLD
  // key. Drop it (and the mirrored smart wallet address) so the file can never
  // describe an agent whose key it no longer holds. Replacing the key with the
  // same value (e.g. a re-save) leaves the identity intact; a missing stored key
  // counts as a change, so a stale agent block can't survive alongside a new key.
  const current = peekWalletFile();
  const currentKey =
    typeof current?.privateKey === "string" ? current.privateKey : undefined;
  if (
    current?.agent &&
    (!currentKey || stripKeyPrefix(currentKey) !== stripKeyPrefix(privateKey))
  ) {
    writeWallet({
      privateKey,
      agent: undefined,
      smartWalletAddress: undefined,
    });
    return;
  }
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

/**
 * A cached Privy session. Bound to one (`address`, `appId`, `origin`) so a session
 * is never reused for a different key, app, or origin. Persisted with 0600
 * permissions because it holds long-lived bearer credentials.
 */
export interface StoredPrivySession {
  version: number;
  /** The EOA that owns this session. */
  address: string;
  appId: string;
  origin: string;
  did: string;
  accessToken: string;
  /** Epoch ms at which the access token expires. */
  accessTokenExpiresAt: number;
  /** Refresh token to exchange for a new access token; absent if Privy didn't issue one. */
  refreshToken?: string;
  identityToken?: string;
}

/**
 * The cached Privy session, or undefined if there is none. A corrupt, unversioned,
 * or structurally-invalid file is treated as absent (with a warning) rather than
 * throwing — the caller simply re-authenticates.
 */
export function getPrivySession(): StoredPrivySession | undefined {
  if (!existsSync(SESSION_FILE)) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(SESSION_FILE, "utf-8"));
  } catch (err) {
    console.error(
      `Warning: could not parse ${SESSION_FILE}: ${formatError(err)}. Ignoring the cached Privy session.`,
    );
    return undefined;
  }
  try {
    assertVersion(parsed, SESSION_VERSION, SESSION_FILE);
  } catch (err) {
    console.error(
      `Warning: ${formatError(err)}. Ignoring the cached Privy session.`,
    );
    return undefined;
  }
  const obj = parsed as Record<string, unknown>;
  if (
    typeof obj.address !== "string" ||
    typeof obj.appId !== "string" ||
    typeof obj.origin !== "string" ||
    typeof obj.did !== "string" ||
    typeof obj.accessToken !== "string" ||
    typeof obj.accessTokenExpiresAt !== "number"
  ) {
    console.error(
      `Warning: ${SESSION_FILE} is missing required fields. Ignoring the cached Privy session.`,
    );
    return undefined;
  }
  return parsed as StoredPrivySession;
}

export function savePrivySession(
  session: Omit<StoredPrivySession, "version">,
): void {
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeSecure(
    SESSION_FILE,
    JSON.stringify({ ...session, version: SESSION_VERSION }, null, 2) + "\n",
  );
}

/** Remove the cached session (e.g. on sign-out). A no-op if there is none. */
export function clearPrivySession(): void {
  if (existsSync(SESSION_FILE)) rmSync(SESSION_FILE, { force: true });
}

export function getSessionPath(): string {
  return SESSION_FILE;
}

/** The window a global spending budget resets over. */
export type BudgetPeriod = "daily" | "weekly" | "lifetime";

/** One recorded spend, appended to the ledger after a successful trade. */
export interface BudgetEntry {
  /** USD value of the trade. */
  usd: number;
  /** The skill (or caller) that made the spend, e.g. "dca". */
  skill: string;
  /** Transaction hash, when known. */
  txHash?: string;
  /** ISO-8601 timestamp of the spend. */
  at: string;
}

/**
 * The agent's global, wallet-level spending budget. Stored separately from the
 * wallet/config so it carries its own append-only ledger. `limitUsd` is the cap
 * for the active window; `null` means no cap is set. `optedOut` records an
 * explicit "no limit, go ahead" acknowledgement — distinct from simply never
 * having configured a budget (no file at all). The active spend is computed from
 * `ledger` against `windowStart`, not stored, so the ledger stays a full audit
 * trail (see {@link spentInWindow}).
 */
export interface BudgetState {
  version: number;
  limitUsd: number | null;
  period: BudgetPeriod;
  optedOut: boolean;
  /** ISO-8601 start of the active window (for daily/weekly); ignored for lifetime. */
  windowStart: string;
  ledger: BudgetEntry[];
}

function isBudgetPeriod(value: unknown): value is BudgetPeriod {
  return value === "daily" || value === "weekly" || value === "lifetime";
}

/**
 * The stored global budget, or undefined if none is configured. A corrupt,
 * unversioned, or structurally-invalid file is treated as absent (with a
 * warning) rather than throwing, matching {@link readConfig}'s behavior — a
 * missing budget simply means "no global cap".
 */
export function getBudget(): BudgetState | undefined {
  if (!existsSync(BUDGET_FILE)) return undefined;
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(BUDGET_FILE, "utf-8"));
  } catch (err) {
    console.error(
      `Warning: could not parse ${BUDGET_FILE}: ${formatError(err)}. Re-run 'zora agent budget set' to reset it.`,
    );
    return undefined;
  }
  try {
    assertVersion(parsed, BUDGET_VERSION, BUDGET_FILE);
  } catch (err) {
    console.error(
      `Warning: ${formatError(err)}. Delete ${BUDGET_FILE} or run 'zora agent budget set' to reset it.`,
    );
    return undefined;
  }
  const obj = parsed as Record<string, unknown>;
  if (
    (obj.limitUsd !== null && typeof obj.limitUsd !== "number") ||
    !isBudgetPeriod(obj.period) ||
    typeof obj.optedOut !== "boolean" ||
    typeof obj.windowStart !== "string" ||
    !Array.isArray(obj.ledger)
  ) {
    console.error(
      `Warning: ${BUDGET_FILE} is missing required fields. Run 'zora agent budget set' to reset it.`,
    );
    return undefined;
  }
  return parsed as BudgetState;
}

export function saveBudget(state: Omit<BudgetState, "version">): void {
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeSecure(
    BUDGET_FILE,
    JSON.stringify({ ...state, version: BUDGET_VERSION }, null, 2) + "\n",
  );
}

/** Remove the stored budget (e.g. `zora agent budget reset --clear`). No-op if absent. */
export function clearBudget(): void {
  if (existsSync(BUDGET_FILE)) rmSync(BUDGET_FILE, { force: true });
}

export function getBudgetPath(): string {
  return BUDGET_FILE;
}
