import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  savePrivateKey: vi.fn(),
  getSmartWalletAddress: vi.fn(),
  getWalletPath: vi.fn(() => "/home/user/.config/zora/wallet.json"),
  peekAgentWallet: vi.fn(),
  getAnalyticsId: vi.fn(),
  getApiKey: vi.fn(),
  saveAnalyticsId: vi.fn(),
}));

vi.mock("../lib/analytics.js");

vi.mock("viem/accounts", () => ({
  generatePrivateKey: vi.fn(),
  privateKeyToAccount: vi.fn(),
}));

vi.mock("../lib/prompt.js", () => ({
  confirmOrDefault: vi.fn(),
  selectOrDefault: vi.fn(),
  passwordOrFail: vi.fn(),
}));

import {
  getPrivateKey,
  savePrivateKey,
  getSmartWalletAddress,
  getWalletPath,
  peekAgentWallet,
} from "../lib/config.js";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import {
  confirmOrDefault,
  selectOrDefault,
  passwordOrFail,
} from "../lib/prompt.js";
import { walletCommand } from "./wallet.js";

const MOCK_KEY = "0x" + "a".repeat(64);
const MOCK_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";
const MOCK_SMART_WALLET = "0xd1373e4119dD2C4C23f11F9cDc97A464790acbC8";

function runWallet(args: string[]) {
  const program = createProgram(walletCommand);
  return program.parseAsync(["wallet", ...args], { from: "user" });
}

beforeEach(() => {
  delete process.env.ZORA_PRIVATE_KEY;
  delete process.env.ZORA_SMART_WALLET_ADDRESS;
  vi.mocked(privateKeyToAccount).mockReturnValue({
    address: MOCK_ADDRESS,
  } as never);
  vi.mocked(getPrivateKey).mockReturnValue(undefined);
  vi.mocked(getSmartWalletAddress).mockReturnValue(undefined);
  vi.mocked(getWalletPath).mockReturnValue(
    "/home/user/.config/zora/wallet.json",
  );
});

afterEach(() => {
  delete process.env.ZORA_PRIVATE_KEY;
  delete process.env.ZORA_SMART_WALLET_ADDRESS;
  vi.resetAllMocks();
});

describe("wallet info", () => {
  it("exits with error when no wallet configured", async () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(runWallet(["info"])).rejects.toThrow("process.exit(1)");
    const allOutput = [
      ...logSpy.mock.calls.map((c) => c[0]),
      ...errorSpy.mock.calls.map((c) => c[0]),
    ].join("\n");
    expect(allOutput).toContain("No wallet configured");
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("treats empty ZORA_PRIVATE_KEY as unset (falls through to file)", async () => {
    process.env.ZORA_PRIVATE_KEY = "";
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(MOCK_ADDRESS));
    logSpy.mockRestore();
  });

  it("shows address from config file", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(MOCK_ADDRESS));
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("/home/user/.config/zora/wallet.json"),
    );
    logSpy.mockRestore();
  });

  it("shows address from ZORA_PRIVATE_KEY env var", async () => {
    process.env.ZORA_PRIVATE_KEY = MOCK_KEY;
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(MOCK_ADDRESS));
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("ZORA_PRIVATE_KEY"),
    );
    logSpy.mockRestore();
  });

  it("shows 'env (ZORA_PRIVATE_KEY)' as source for env var", async () => {
    process.env.ZORA_PRIVATE_KEY = MOCK_KEY;
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("env (ZORA_PRIVATE_KEY)"),
    );
    logSpy.mockRestore();
  });

  it("exits with error on invalid stored key", async () => {
    vi.mocked(getPrivateKey).mockReturnValue("bad-key");
    vi.mocked(privateKeyToAccount).mockImplementation(() => {
      throw new Error("invalid key");
    });
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(runWallet(["info"])).rejects.toThrow("process.exit(1)");
    const allOutput = [
      ...logSpy.mock.calls.map((c) => c[0]),
      ...errorSpy.mock.calls.map((c) => c[0]),
    ].join("\n");
    expect(allOutput).toContain("invalid");
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("shows the configured smart wallet address as the primary address", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(getSmartWalletAddress).mockReturnValue(MOCK_SMART_WALLET);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(`Smart wallet: ${MOCK_SMART_WALLET}`),
    );
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(`Owner (EOA):  ${MOCK_ADDRESS}`),
    );
    logSpy.mockRestore();
  });

  it("prefers ZORA_SMART_WALLET_ADDRESS over the stored smart wallet", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(getSmartWalletAddress).mockReturnValue(MOCK_SMART_WALLET);
    process.env.ZORA_SMART_WALLET_ADDRESS = MOCK_ADDRESS;
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(`Smart wallet: ${MOCK_ADDRESS}`),
    );
    logSpy.mockRestore();
  });

  it("emits the smart wallet as `address` in JSON output", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(getSmartWalletAddress).mockReturnValue(MOCK_SMART_WALLET);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info", "--json"]);

    const payload = JSON.parse(logSpy.mock.calls[0][0] as string);
    expect(payload).toMatchObject({
      address: MOCK_SMART_WALLET,
      smartWalletAddress: MOCK_SMART_WALLET,
      ownerAddress: MOCK_ADDRESS,
    });
    logSpy.mockRestore();
  });

  it("falls back to the EOA when no smart wallet is configured", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining(`Address: ${MOCK_ADDRESS}`),
    );
    expect(logSpy).not.toHaveBeenCalledWith(
      expect.stringContaining("Smart wallet:"),
    );
    logSpy.mockRestore();
  });

  it("exits with error on invalid configured smart wallet address", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    process.env.ZORA_SMART_WALLET_ADDRESS = "not-an-address";
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(runWallet(["info"])).rejects.toThrow("process.exit(1)");
    const allOutput = [
      ...logSpy.mock.calls.map((c) => c[0]),
      ...errorSpy.mock.calls.map((c) => c[0]),
    ].join("\n");
    expect(allOutput).toContain("not a valid address");
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

describe("wallet export", () => {
  it("exits with error when no wallet configured", async () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(runWallet(["export", "--force"])).rejects.toThrow(
      "process.exit(1)",
    );
    const allOutput = [
      ...logSpy.mock.calls.map((c) => c[0]),
      ...errorSpy.mock.calls.map((c) => c[0]),
    ].join("\n");
    expect(allOutput).toContain("No wallet configured");
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("prints key with --force (no prompt)", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["export", "--force"]);

    expect(logSpy).toHaveBeenCalledWith(MOCK_KEY);
    expect(confirmOrDefault).not.toHaveBeenCalled();
    logSpy.mockRestore();
  });

  it("prompts for confirmation without --force", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(confirmOrDefault).mockResolvedValue(true);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["export"]);

    expect(confirmOrDefault).toHaveBeenCalled();
    expect(logSpy).toHaveBeenCalledWith(MOCK_KEY);
    logSpy.mockRestore();
  });

  it("shows safety warning before prompt", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(confirmOrDefault).mockResolvedValue(true);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["export"]);

    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("private key grants full access"),
    );
    logSpy.mockRestore();
  });

  it("aborts when user declines confirmation", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(confirmOrDefault).mockResolvedValue(false);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(runWallet(["export"])).rejects.toThrow("process.exit(0)");
    expect(logSpy).not.toHaveBeenCalledWith(MOCK_KEY);
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("prints env var key with --force", async () => {
    process.env.ZORA_PRIVATE_KEY = MOCK_KEY;
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["export", "--force"]);

    expect(logSpy).toHaveBeenCalledWith(MOCK_KEY);
    logSpy.mockRestore();
  });
});

describe("wallet configure", () => {
  const NEW_KEY = ("0x" + "b".repeat(64)) as `0x${string}`;

  it("creates a new wallet with --create", async () => {
    vi.mocked(generatePrivateKey).mockReturnValue(NEW_KEY);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["configure", "--create"]);

    expect(savePrivateKey).toHaveBeenCalledWith(NEW_KEY);
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("\u2713 Wallet created"),
    );
    logSpy.mockRestore();
  });

  it("imports a key via prompt", async () => {
    vi.mocked(selectOrDefault).mockResolvedValue("import" as never);
    vi.mocked(passwordOrFail).mockResolvedValue("a".repeat(64));
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["configure"]);

    expect(savePrivateKey).toHaveBeenCalledWith("a".repeat(64));
    expect(logSpy).toHaveBeenCalledWith(
      expect.stringContaining("\u2713 Wallet imported"),
    );
    logSpy.mockRestore();
  });

  it("errors when wallet exists without --force", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(runWallet(["configure", "--create"])).rejects.toThrow(
      "process.exit(1)",
    );

    const allOutput = [
      ...logSpy.mock.calls.map((c) => c[0]),
      ...errorSpy.mock.calls.map((c) => c[0]),
    ].join("\n");
    expect(allOutput).toContain("--force");
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("overwrites wallet with --force", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(generatePrivateKey).mockReturnValue(NEW_KEY);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["configure", "--create", "--force"]);

    expect(savePrivateKey).toHaveBeenCalledWith(NEW_KEY);
    logSpy.mockRestore();
  });
});

describe("wallet configure (agent wallet)", () => {
  const AGENT = {
    address: "0xAbC0000000000000000000000000000000000001",
    embeddedWalletAddress: "0xEeE0000000000000000000000000000000000001",
    smartWalletAddress: "0xd1373e4119dD2C4C23f11F9cDc97A464790acbC8",
    did: "did:privy:test",
    username: "keen_cedar_9807",
    profileUrl: "https://zora.co/@keen_cedar_9807",
    createdAt: "2026-06-10T00:00:00.000Z",
  } as const;
  const REPLACEMENT = ("0x" + "b".repeat(64)) as `0x${string}`;

  it("refuses to overwrite non-interactively, even with --force --yes", async () => {
    vi.mocked(peekAgentWallet).mockReturnValue(AGENT);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(
      runWallet(["configure", "--create", "--force", "--yes"]),
    ).rejects.toThrow("process.exit(1)");

    expect(savePrivateKey).not.toHaveBeenCalled();
    const out = [
      ...logSpy.mock.calls.map((c) => c[0]),
      ...errorSpy.mock.calls.map((c) => c[0]),
    ].join("\n");
    expect(out).toContain("keen_cedar_9807");
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("prompts before overwriting and proceeds when confirmed", async () => {
    vi.mocked(peekAgentWallet).mockReturnValue(AGENT);
    vi.mocked(confirmOrDefault).mockResolvedValue(true);
    vi.mocked(generatePrivateKey).mockReturnValue(REPLACEMENT);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    await runWallet(["configure", "--create"]);

    expect(confirmOrDefault).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("keen_cedar_9807"),
      }),
      false,
    );
    expect(savePrivateKey).toHaveBeenCalledWith(REPLACEMENT);
    logSpy.mockRestore();
    errorSpy.mockRestore();
  });

  it("treats --force as no bypass: still prompts, aborts when declined", async () => {
    vi.mocked(peekAgentWallet).mockReturnValue(AGENT);
    vi.mocked(confirmOrDefault).mockResolvedValue(false);
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(
      runWallet(["configure", "--create", "--force"]),
    ).rejects.toThrow("process.exit(0)");

    expect(confirmOrDefault).toHaveBeenCalled();
    expect(savePrivateKey).not.toHaveBeenCalled();
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });
});
