import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  chmodSync,
} from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

const CONFIG_DIR = join(homedir(), ".config", "zora");
const CONFIG_FILE = join(CONFIG_DIR, "config.json");

const WALLET_FILE = join(CONFIG_DIR, "wallet.json");

const CONFIG_VERSION = 1;
const WALLET_VERSION = 1;

interface Config {
  version: number;
  apiKey?: string;
}

interface Wallet {
  version: number;
  privateKey: string;
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

function readConfig(): Config {
  if (!existsSync(CONFIG_FILE)) return { version: CONFIG_VERSION };
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(CONFIG_FILE, "utf-8"));
  } catch (err) {
    console.error(
      `Warning: could not parse ${CONFIG_FILE}: ${(err as Error).message}. Run 'zora auth configure' to fix.`,
    );
    return { version: CONFIG_VERSION };
  }
  try {
    assertVersion(parsed, CONFIG_VERSION, CONFIG_FILE);
  } catch (err) {
    console.error(
      `Error: ${(err as Error).message}. Delete ${CONFIG_FILE} or run 'zora auth configure' to reset.`,
    );
    process.exit(1);
  }
  return parsed as Config;
}

function writeConfig(config: Config): void {
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(
    CONFIG_FILE,
    JSON.stringify({ ...config, version: CONFIG_VERSION }, null, 2) + "\n",
    {
      mode: 0o600,
    },
  );
  chmodSync(CONFIG_FILE, 0o600);
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
  return parsed as Wallet;
}

function writeWallet(wallet: Omit<Wallet, "version">): void {
  mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(
    WALLET_FILE,
    JSON.stringify({ ...wallet, version: WALLET_VERSION }, null, 2) + "\n",
    {
      mode: 0o600,
    },
  );
  chmodSync(WALLET_FILE, 0o600);
}

/** Returns the env-var key if set (errors on empty), or undefined if unset. */
export function getEnvApiKey(): string | undefined {
  const envKey = process.env.ZORA_API_KEY;
  if (envKey === undefined) return undefined;
  if (!envKey) {
    console.error(
      "ZORA_API_KEY is set but empty. Provide a valid key or unset the variable.",
    );
    process.exit(1);
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

export function getWalletPath(): string {
  return WALLET_FILE;
}

export function getConfigPath(): string {
  return CONFIG_FILE;
}
