import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  getWalletPath: vi.fn(() => "/home/user/.config/zora/wallet.json"),
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: vi.fn(),
}));

vi.mock("../lib/prompt.js", () => ({
  confirmOrDefault: vi.fn(),
}));

import { getPrivateKey } from "../lib/config.js";
import { privateKeyToAccount } from "viem/accounts";
import { confirmOrDefault } from "../lib/prompt.js";

const MOCK_KEY = "0x" + "a".repeat(64);
const MOCK_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";

async function runWallet(args: string[]) {
  const { walletCommand } = await import("./wallet.js");
  const program = createProgram(walletCommand);
  return program.parseAsync(["wallet", ...args], { from: "user" });
}

beforeEach(() => {
  delete process.env.ZORA_PRIVATE_KEY;
  vi.mocked(privateKeyToAccount).mockReturnValue({ address: MOCK_ADDRESS } as never);
  vi.mocked(getPrivateKey).mockReturnValue(undefined);
});

afterEach(() => {
  delete process.env.ZORA_PRIVATE_KEY;
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
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("/home/user/.config/zora/wallet.json"));
    logSpy.mockRestore();
  });

  it("shows address from ZORA_PRIVATE_KEY env var", async () => {
    process.env.ZORA_PRIVATE_KEY = MOCK_KEY;
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(MOCK_ADDRESS));
    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("ZORA_PRIVATE_KEY"));
    logSpy.mockRestore();
  });

  it("shows 'env (ZORA_PRIVATE_KEY)' as source for env var", async () => {
    process.env.ZORA_PRIVATE_KEY = MOCK_KEY;
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});

    await runWallet(["info"]);

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("env (ZORA_PRIVATE_KEY)"));
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
});

describe("wallet export", () => {
  it("exits with error when no wallet configured", async () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    await expect(runWallet(["export", "--force"])).rejects.toThrow("process.exit(1)");
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

    expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("private key grants full access"));
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
