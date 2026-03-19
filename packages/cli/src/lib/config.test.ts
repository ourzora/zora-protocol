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
    const exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation(() => undefined as never);
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getEnvApiKey } = await loadConfig();
    process.env.ZORA_API_KEY = "";
    getEnvApiKey();
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("ZORA_API_KEY is set but empty"),
    );
    exitSpy.mockRestore();
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
    const exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation(() => undefined as never);
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getApiKey } = await loadConfig();
    process.env.ZORA_API_KEY = "";
    getApiKey();
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("ZORA_API_KEY is set but empty"),
    );
    exitSpy.mockRestore();
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

  it("exits with error on config version mismatch (does not silently reset to defaults)", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "config.json"),
      JSON.stringify({ version: 99, apiKey: "my-key" }),
    );
    const exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation(() => undefined as never);
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getApiKey } = await loadConfig();
    getApiKey();
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("unsupported version"),
    );
    exitSpy.mockRestore();
    errorSpy.mockRestore();
  });

  it("exits with error on config missing version field", async () => {
    const configDir = join(getTestHomeDir(), ".config", "zora");
    mkdirSync(configDir, { recursive: true });
    writeFileSync(
      join(configDir, "config.json"),
      JSON.stringify({ apiKey: "my-key" }),
    );
    const exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation(() => undefined as never);
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { getApiKey } = await loadConfig();
    getApiKey();
    expect(exitSpy).toHaveBeenCalledWith(1);
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("missing required field"),
    );
    exitSpy.mockRestore();
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
