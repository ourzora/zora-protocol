import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdirSync, statSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { getTestHomeDir } from "../test/setup.js";

beforeEach(() => {
  delete process.env.ZORA_API_KEY;
});

afterEach(() => {
  delete process.env.ZORA_API_KEY;
});

async function loadConfig() {
  return await import("./config.js");
}

describe("getEnvApiKey", () => {
  it("returns undefined when ZORA_API_KEY is not set", async () => {
    const { getEnvApiKey } = await loadConfig();
    expect(getEnvApiKey()).toBeUndefined();
  });

  it("returns the env var value when set", async () => {
    process.env.ZORA_API_KEY = "env-key-123";
    const { getEnvApiKey } = await loadConfig();
    expect(getEnvApiKey()).toBe("env-key-123");
  });

  it("exits with error when env var is empty string", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getEnvApiKey } = await loadConfig();
    process.env.ZORA_API_KEY = "";
    expect(() => getEnvApiKey()).toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("ZORA_API_KEY is set but empty"),
    );
    errorSpy.mockRestore();
  });
});

describe("getApiKey", () => {
  it("returns undefined when no key is configured", async () => {
    const { getApiKey } = await loadConfig();
    expect(getApiKey()).toBeUndefined();
  });

  it("returns env var when ZORA_API_KEY is set", async () => {
    process.env.ZORA_API_KEY = "env-key-123";
    const { getApiKey } = await loadConfig();
    expect(getApiKey()).toBe("env-key-123");
  });

  it("returns saved key from config file", async () => {
    const { saveApiKey, getApiKey } = await loadConfig();
    saveApiKey("saved-key-456");
    expect(getApiKey()).toBe("saved-key-456");
  });

  it("env var takes precedence over config file", async () => {
    const { saveApiKey, getApiKey } = await loadConfig();
    saveApiKey("saved-key");
    process.env.ZORA_API_KEY = "env-key";
    expect(getApiKey()).toBe("env-key");
  });

  it("empty env var exits with error", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getApiKey } = await loadConfig();
    process.env.ZORA_API_KEY = "";
    expect(() => getApiKey()).toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("ZORA_API_KEY is set but empty"),
    );
    errorSpy.mockRestore();
  });

  it("warns on corrupted config file", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(join(configDir, "config.json"), "not json{{{");
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getApiKey } = await loadConfig();
    expect(getApiKey()).toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("could not parse"),
    );
    errorSpy.mockRestore();
  });

  it("warns and returns undefined on config version mismatch", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "config.json"),
      JSON.stringify({ version: 99, apiKey: "my-key" }),
    );
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getApiKey } = await loadConfig();
    expect(getApiKey()).toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("unsupported version"),
    );
    errorSpy.mockRestore();
  });

  it("warns and returns undefined on config missing version field", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "config.json"),
      JSON.stringify({ apiKey: "my-key" }),
    );
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getApiKey } = await loadConfig();
    expect(getApiKey()).toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("missing required field"),
    );
    errorSpy.mockRestore();
  });
});

describe("saveApiKey", () => {
  it("creates config directory and file with version", async () => {
    const { saveApiKey, getConfigPath } = await loadConfig();
    saveApiKey("test-key");
    const content = JSON.parse(readFileSync(getConfigPath(), "utf-8"));
    expect(content.apiKey).toBe("test-key");
    expect(content.version).toBe(1);
  });

  it("sets file permissions to 0600", async () => {
    const { saveApiKey, getConfigPath } = await loadConfig();
    saveApiKey("test-key");
    const stats = statSync(getConfigPath());
    expect(stats.mode & 0o777).toBe(0o600);
  });

  it("overwrites existing key", async () => {
    const { saveApiKey, getApiKey } = await loadConfig();
    saveApiKey("first-key");
    saveApiKey("second-key");
    expect(getApiKey()).toBe("second-key");
  });
});

describe("getConfigPath", () => {
  it("returns path under ~/.config/zora/", async () => {
    const { getConfigPath } = await loadConfig();
    expect(getConfigPath()).toBe(
      join(getTestHomeDir(), ".config", "zora", "config.json"),
    );
  });
});

describe("savePrivateKey / getPrivateKey", () => {
  it("returns undefined when no wallet file exists", async () => {
    const { getPrivateKey } = await loadConfig();
    expect(getPrivateKey()).toBeUndefined();
  });

  it("saves and retrieves a private key", async () => {
    const { savePrivateKey, getPrivateKey } = await loadConfig();
    const key = "0x" + "a".repeat(64);
    savePrivateKey(key);
    expect(getPrivateKey()).toBe(key);
  });

  it("writes version: 1 to wallet file", async () => {
    const { savePrivateKey, getWalletPath } = await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    const content = JSON.parse(readFileSync(getWalletPath(), "utf-8"));
    expect(content.version).toBe(1);
  });

  it("creates ~/.config/zora/ directory and sets file permissions to 0600", async () => {
    const { savePrivateKey, getWalletPath } = await loadConfig();
    savePrivateKey("0x" + "b".repeat(64));
    const stats = statSync(getWalletPath());
    expect(stats.mode & 0o777).toBe(0o600);
  });

  it("overwrites an existing private key", async () => {
    const { savePrivateKey, getPrivateKey } = await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    savePrivateKey("0x" + "b".repeat(64));
    expect(getPrivateKey()).toBe("0x" + "b".repeat(64));
  });

  it("throws on corrupted wallet file", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(join(configDir, "wallet.json"), "not json{{{");
    const { getPrivateKey } = await loadConfig();
    expect(() => getPrivateKey()).toThrow();
  });

  it("includes file path in error for corrupted wallet file", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(join(configDir, "wallet.json"), "not json{{{");
    const { getPrivateKey, getWalletPath } = await loadConfig();
    expect(() => getPrivateKey()).toThrow(getWalletPath());
  });

  it("throws when wallet file is missing version field", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({ privateKey: "0x" + "a".repeat(64) }),
    );
    const { getPrivateKey } = await loadConfig();
    expect(() => getPrivateKey()).toThrow(/missing required field "version"/);
  });

  it("throws when wallet file has wrong version", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({ version: 99, privateKey: "0x" + "a".repeat(64) }),
    );
    const { getPrivateKey } = await loadConfig();
    expect(() => getPrivateKey()).toThrow(/unsupported version/);
  });

  it("throws when wallet file has missing privateKey field", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({ version: 1 }),
    );
    const { getPrivateKey } = await loadConfig();
    expect(() => getPrivateKey()).toThrow(/missing or invalid "privateKey"/);
  });

  it("throws when wallet file has null privateKey", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({ version: 1, privateKey: null }),
    );
    const { getPrivateKey } = await loadConfig();
    expect(() => getPrivateKey()).toThrow(/missing or invalid "privateKey"/);
  });
});

describe("getWalletPath", () => {
  it("returns path under ~/.config/zora/", async () => {
    const { getWalletPath } = await loadConfig();
    expect(getWalletPath()).toBe(
      join(getTestHomeDir(), ".config", "zora", "wallet.json"),
    );
  });
});

describe("Privy session store", () => {
  const fullSession = {
    address: "0x000000000000000000000000000000000000c0de",
    appId: "app-123",
    origin: "https://zora.com",
    did: "did:privy:abc",
    accessToken: "access.jwt",
    accessTokenExpiresAt: 1_900_000_000_000,
    refreshToken: "refresh-token",
    identityToken: "identity.jwt",
  };

  it("returns undefined when no session file exists", async () => {
    const { getPrivySession } = await loadConfig();
    expect(getPrivySession()).toBeUndefined();
  });

  it("saves and round-trips a session", async () => {
    const { savePrivySession, getPrivySession } = await loadConfig();
    savePrivySession(fullSession);
    expect(getPrivySession()).toEqual({ ...fullSession, version: 1 });
  });

  it("writes version: 1 and 0600 permissions", async () => {
    const { savePrivySession, getSessionPath } = await loadConfig();
    savePrivySession(fullSession);
    const content = JSON.parse(readFileSync(getSessionPath(), "utf-8"));
    expect(content.version).toBe(1);
    expect(statSync(getSessionPath()).mode & 0o777).toBe(0o600);
  });

  it("clears the session", async () => {
    const { savePrivySession, clearPrivySession, getPrivySession } =
      await loadConfig();
    savePrivySession(fullSession);
    clearPrivySession();
    expect(getPrivySession()).toBeUndefined();
  });

  it("clearPrivySession is a no-op when there is no session", async () => {
    const { clearPrivySession, getPrivySession } = await loadConfig();
    expect(() => clearPrivySession()).not.toThrow();
    expect(getPrivySession()).toBeUndefined();
  });

  it("warns and ignores a corrupt session file", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(join(configDir, "session.json"), "not json{{{");
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getPrivySession } = await loadConfig();
    expect(getPrivySession()).toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("could not parse"),
    );
    errorSpy.mockRestore();
  });

  it("warns and ignores a session with an unsupported version", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "session.json"),
      JSON.stringify({ ...fullSession, version: 99 }),
    );
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getPrivySession } = await loadConfig();
    expect(getPrivySession()).toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("unsupported version"),
    );
    errorSpy.mockRestore();
  });

  it("warns and ignores a session missing required fields", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "session.json"),
      JSON.stringify({ version: 1, address: "0xabc" }),
    );
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getPrivySession } = await loadConfig();
    expect(getPrivySession()).toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("missing required fields"),
    );
    errorSpy.mockRestore();
  });

  it("warns and ignores a session missing the did field", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    const { did: _omit, ...withoutDid } = fullSession;
    writeFileSync(
      join(configDir, "session.json"),
      JSON.stringify({ version: 1, ...withoutDid }),
    );
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getPrivySession } = await loadConfig();
    expect(getPrivySession()).toBeUndefined();
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("missing required fields"),
    );
    errorSpy.mockRestore();
  });

  it("getSessionPath returns a path under ~/.config/zora/", async () => {
    const { getSessionPath } = await loadConfig();
    expect(getSessionPath()).toBe(
      join(getTestHomeDir(), ".config", "zora", "session.json"),
    );
  });
});

const AGENT_INFO = {
  address: "0xabc0000000000000000000000000000000000001",
  embeddedWalletAddress: "0xeee0000000000000000000000000000000000001",
  smartWalletAddress: "0xd1373e4119dd2c4c23f11f9cdc97a464790acbc8",
  did: "did:privy:test123",
  username: "keen_cedar_9807",
  profileUrl: "https://zora.co/@keen_cedar_9807",
  createdAt: "2026-06-10T00:00:00.000Z",
} as const;

describe("saveAgentWallet / getAgentWallet / isAgentWallet", () => {
  it("reports no agent identity when no wallet file exists", async () => {
    const { getAgentWallet, isAgentWallet } = await loadConfig();
    expect(getAgentWallet()).toBeUndefined();
    expect(isAgentWallet()).toBe(false);
  });

  it("reports no agent identity for a key-only wallet", async () => {
    const { savePrivateKey, getAgentWallet, isAgentWallet } =
      await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    expect(getAgentWallet()).toBeUndefined();
    expect(isAgentWallet()).toBe(false);
  });

  it("saves and retrieves the full agent identity", async () => {
    const { savePrivateKey, saveAgentWallet, getAgentWallet, isAgentWallet } =
      await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    saveAgentWallet(AGENT_INFO);
    expect(getAgentWallet()).toEqual(AGENT_INFO);
    expect(isAgentWallet()).toBe(true);
  });

  it("mirrors the smart wallet address to the top-level field", async () => {
    const { savePrivateKey, saveAgentWallet, getSmartWalletAddress } =
      await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    saveAgentWallet(AGENT_INFO);
    expect(getSmartWalletAddress()).toBe(AGENT_INFO.smartWalletAddress);
  });

  it("preserves an existing private key when saving the identity", async () => {
    const { savePrivateKey, saveAgentWallet, getPrivateKey } =
      await loadConfig();
    const key = "0x" + "a".repeat(64);
    savePrivateKey(key);
    saveAgentWallet(AGENT_INFO);
    expect(getPrivateKey()).toBe(key);
  });

  it("writes version 1, the agent block, and sets file permissions to 0600", async () => {
    const { savePrivateKey, saveAgentWallet, getAgentWallet, getWalletPath } =
      await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    saveAgentWallet(AGENT_INFO);
    const content = JSON.parse(readFileSync(getWalletPath(), "utf-8"));
    expect(content.version).toBe(1);
    expect(content.agent).toEqual(AGENT_INFO);
    expect(statSync(getWalletPath()).mode & 0o777).toBe(0o600);
    // the written file round-trips through readWallet() without throwing
    expect(getAgentWallet()).toEqual(AGENT_INFO);
  });

  it("throws when the agent block has an invalid address", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({
        version: 1,
        privateKey: "0x" + "a".repeat(64),
        agent: { ...AGENT_INFO, smartWalletAddress: "not-an-address" },
      }),
    );
    const { getAgentWallet } = await loadConfig();
    expect(() => getAgentWallet()).toThrow(
      /invalid "agent.smartWalletAddress"/,
    );
  });

  it("throws when the agent block is missing a required string field", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({
        version: 1,
        privateKey: "0x" + "a".repeat(64),
        agent: { ...AGENT_INFO, did: undefined },
      }),
    );
    const { getAgentWallet } = await loadConfig();
    expect(() => getAgentWallet()).toThrow(/missing or invalid "agent.did"/);
  });
});

describe("savePrivateKey drops a stale agent identity", () => {
  it("removes the agent block when the key actually changes", async () => {
    const {
      savePrivateKey,
      saveAgentWallet,
      getAgentWallet,
      getSmartWalletAddress,
      getPrivateKey,
      peekAgentWallet,
    } = await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    saveAgentWallet(AGENT_INFO);
    expect(getAgentWallet()).toEqual(AGENT_INFO);

    // The recorded agent was owned by the old key — replacing it invalidates it.
    savePrivateKey("0x" + "b".repeat(64));
    expect(getPrivateKey()).toBe("0x" + "b".repeat(64));
    expect(getAgentWallet()).toBeUndefined();
    expect(peekAgentWallet()).toBeUndefined();
    expect(getSmartWalletAddress()).toBeUndefined();
  });

  it("keeps the agent block when the same key is re-saved", async () => {
    const { savePrivateKey, saveAgentWallet, getAgentWallet } =
      await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    saveAgentWallet(AGENT_INFO);
    savePrivateKey("0x" + "a".repeat(64));
    expect(getAgentWallet()).toEqual(AGENT_INFO);
  });

  it("compares keys ignoring a 0x prefix", async () => {
    const { savePrivateKey, saveAgentWallet, getAgentWallet } =
      await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    saveAgentWallet(AGENT_INFO);
    savePrivateKey("a".repeat(64));
    expect(getAgentWallet()).toEqual(AGENT_INFO);
  });

  it("drops the agent block when the file has an agent but no stored key", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    // An agent block with no privateKey can't belong to the key being saved, so
    // the stale identity must not survive alongside the new key.
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({ version: 1, agent: AGENT_INFO }),
    );
    const { savePrivateKey, getPrivateKey, peekAgentWallet } =
      await loadConfig();
    savePrivateKey("0x" + "b".repeat(64));
    expect(getPrivateKey()).toBe("0x" + "b".repeat(64));
    expect(peekAgentWallet()).toBeUndefined();
  });
});

describe("peekAgentWallet", () => {
  it("returns undefined when no wallet file exists", async () => {
    const { peekAgentWallet } = await loadConfig();
    expect(peekAgentWallet()).toBeUndefined();
  });

  it("returns the agent identity from a valid wallet file", async () => {
    const { savePrivateKey, saveAgentWallet, peekAgentWallet } =
      await loadConfig();
    savePrivateKey("0x" + "a".repeat(64));
    saveAgentWallet(AGENT_INFO);
    expect(peekAgentWallet()).toMatchObject({
      username: AGENT_INFO.username,
      smartWalletAddress: AGENT_INFO.smartWalletAddress,
    });
  });

  it("detects an agent even when the wallet file is otherwise malformed", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    // A corrupt private key would make readWallet() throw, but the guard must
    // still recognize the agent so it can protect it.
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({ version: 1, privateKey: 12345, agent: AGENT_INFO }),
    );
    const { peekAgentWallet, getAgentWallet } = await loadConfig();
    expect(() => getAgentWallet()).toThrow();
    expect(peekAgentWallet()).toMatchObject({ username: AGENT_INFO.username });
  });

  it("returns undefined when the agent block is missing the address field", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    const { address: _omit, ...agentWithoutAddress } = AGENT_INFO;
    writeFileSync(
      join(configDir, "wallet.json"),
      JSON.stringify({
        version: 1,
        privateKey: "0x" + "a".repeat(64),
        agent: agentWithoutAddress,
      }),
    );
    const { peekAgentWallet } = await loadConfig();
    // The guard reads agent.address; without it, treat the block as unusable
    // rather than risk a TypeError downstream.
    expect(peekAgentWallet()).toBeUndefined();
  });
});
