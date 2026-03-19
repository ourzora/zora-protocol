import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  savePrivateKey: vi.fn(),
  getWalletPath: vi.fn(() => "/tmp/.zora/wallet.json"),
}));

vi.mock("viem/accounts", () => ({
  generatePrivateKey: vi.fn(),
  privateKeyToAccount: vi.fn(),
}));

vi.mock("../lib/prompt.js", () => ({
  selectOrDefault: vi.fn(),
  passwordOrFail: vi.fn(),
}));

import { getPrivateKey, savePrivateKey } from "../lib/config.js";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { selectOrDefault, passwordOrFail } from "../lib/prompt.js";

const MOCK_KEY = ("0x" + "a".repeat(64)) as `0x${string}`;
const MOCK_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";

async function runSetup(args: string[] = []) {
  const { setupCommand } = await import("./setup.js");
  const program = createProgram(setupCommand);
  await program.parseAsync(["setup", ...args], { from: "user" });
}

describe("setup command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });
    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    vi.mocked(generatePrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(privateKeyToAccount).mockReturnValue({ address: MOCK_ADDRESS } as ReturnType<typeof privateKeyToAccount>);
    delete process.env.ZORA_PRIVATE_KEY;
  });

  afterEach(() => {
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
    vi.clearAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
  });

  describe("--create flag (no prompt)", () => {
    it("generates a key, saves it, and prints success", async () => {
      await runSetup(["--create"]);

      expect(generatePrivateKey).toHaveBeenCalled();
      expect(savePrivateKey).toHaveBeenCalledWith(MOCK_KEY);
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("\u2713 Wallet created"));
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(MOCK_ADDRESS));
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("/tmp/.zora/wallet.json"));
    });

    it("does not show the interactive prompt", async () => {
      await runSetup(["--create"]);
      expect(selectOrDefault).not.toHaveBeenCalled();
    });
  });

  describe("interactive select prompt", () => {
    it("prompts and creates wallet when user selects 'create'", async () => {
      vi.mocked(selectOrDefault).mockResolvedValue("create" as never);

      await runSetup([]);

      expect(selectOrDefault).toHaveBeenCalledWith(
        expect.objectContaining({ message: "How do you want to set up your wallet?" }),
        false,
      );
      expect(savePrivateKey).toHaveBeenCalledWith(MOCK_KEY);
    });
  });

  describe("import path", () => {
    it("saves imported key and shows success on valid input", async () => {
      vi.mocked(selectOrDefault).mockResolvedValue("import" as never);
      vi.mocked(passwordOrFail).mockResolvedValue("a".repeat(64));

      await runSetup([]);

      expect(savePrivateKey).toHaveBeenCalledWith("a".repeat(64));
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("\u2713 Wallet imported"));
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(MOCK_ADDRESS));
    });

    it("accepts key with 0x prefix", async () => {
      vi.mocked(selectOrDefault).mockResolvedValue("import" as never);
      vi.mocked(passwordOrFail).mockResolvedValue("0x" + "a".repeat(64));

      await runSetup([]);

      expect(savePrivateKey).toHaveBeenCalledWith("0x" + "a".repeat(64));
    });

    it("re-prompts on invalid input, then accepts valid key", async () => {
      vi.mocked(selectOrDefault).mockResolvedValue("import" as never);
      vi.mocked(passwordOrFail)
        .mockResolvedValueOnce("bad-key")
        .mockResolvedValueOnce("a".repeat(64));

      await runSetup([]);

      expect(passwordOrFail).toHaveBeenCalledTimes(2);
      expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Not a valid private key"));
      expect(savePrivateKey).toHaveBeenCalledWith("a".repeat(64));
    });

    it("trims whitespace from pasted key", async () => {
      vi.mocked(selectOrDefault).mockResolvedValue("import" as never);
      vi.mocked(passwordOrFail).mockResolvedValue("  " + "a".repeat(64) + "  ");

      await runSetup([]);

      expect(savePrivateKey).toHaveBeenCalledWith("a".repeat(64));
    });
  });

  describe("existing wallet guard", () => {
    it("exits with error if wallet exists and --force not set", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);

      await expect(runSetup(["--create"])).rejects.toThrow("process.exit(1)");

      const allOutput = [
        ...logSpy.mock.calls.map((c) => c[0]),
        ...errorSpy.mock.calls.map((c) => c[0]),
      ].join("\n");
      expect(allOutput).toContain("--force");
      expect(savePrivateKey).not.toHaveBeenCalled();
    });

    it("shows truncated existing address before blocking", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);

      await expect(runSetup(["--create"])).rejects.toThrow("process.exit(1)");

      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("Wallet already configured:"));
    });

    it("overwrites existing wallet when --force is set", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
      const newKey = ("0x" + "b".repeat(64)) as `0x${string}`;
      vi.mocked(generatePrivateKey).mockReturnValue(newKey);

      await runSetup(["--create", "--force"]);

      expect(savePrivateKey).toHaveBeenCalledWith(newKey);
      expect(exitSpy).not.toHaveBeenCalled();
    });
  });

  describe("ZORA_PRIVATE_KEY env var", () => {
    it("uses env var and skips wallet creation", async () => {
      process.env.ZORA_PRIVATE_KEY = "a".repeat(64);

      await runSetup([]);

      expect(savePrivateKey).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("ZORA_PRIVATE_KEY"));
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining(MOCK_ADDRESS));
    });

    it("uses env var with 0x prefix", async () => {
      process.env.ZORA_PRIVATE_KEY = "0x" + "a".repeat(64);

      await runSetup([]);

      expect(savePrivateKey).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("ZORA_PRIVATE_KEY"));
    });

    it("exits with error for invalid env var value", async () => {
      process.env.ZORA_PRIVATE_KEY = "not-a-valid-key";

      await expect(runSetup([])).rejects.toThrow("process.exit(1)");

      const allOutput = [
        ...logSpy.mock.calls.map((c) => c[0]),
        ...errorSpy.mock.calls.map((c) => c[0]),
      ].join("\n");
      expect(allOutput).toContain("ZORA_PRIVATE_KEY isn't a valid private key");
    });

    it("exits with pretty error when privateKeyToAccount throws (curve-invalid key)", async () => {
      process.env.ZORA_PRIVATE_KEY = "a".repeat(64);
      vi.mocked(privateKeyToAccount).mockImplementation(() => {
        throw new Error("invalid private key");
      });

      await expect(runSetup([])).rejects.toThrow("process.exit(1)");

      const allOutput = [
        ...logSpy.mock.calls.map((c) => c[0]),
        ...errorSpy.mock.calls.map((c) => c[0]),
      ].join("\n");
      expect(allOutput).toContain("ZORA_PRIVATE_KEY");
      expect(allOutput).toContain("isn't a valid private key");
    });
  });

  describe("corrupted wallet file", () => {
    it("exits with friendly error when getPrivateKey throws", async () => {
      vi.mocked(getPrivateKey).mockImplementation(() => {
        throw new Error("/home/user/.config/zora/wallet.json: Unexpected token");
      });

      await expect(runSetup(["--create"])).rejects.toThrow("process.exit(1)");

      const allOutput = [
        ...logSpy.mock.calls.map((c) => c[0]),
        ...errorSpy.mock.calls.map((c) => c[0]),
      ].join("\n");
      expect(allOutput).toContain("Could not read wallet");
      expect(allOutput).toContain("--force");
    });

    it("--force skips reading the corrupted wallet and proceeds", async () => {
      vi.mocked(getPrivateKey).mockImplementation(() => {
        throw new Error("/home/user/.config/zora/wallet.json: Unexpected token");
      });
      const newKey = ("0x" + "c".repeat(64)) as `0x${string}`;
      vi.mocked(generatePrivateKey).mockReturnValue(newKey);

      await runSetup(["--create", "--force"]);

      expect(getPrivateKey).not.toHaveBeenCalled();
      expect(savePrivateKey).toHaveBeenCalledWith(newKey);
      expect(exitSpy).not.toHaveBeenCalled();
    });
  });

  describe("save failure", () => {
    it("exits with error when savePrivateKey throws", async () => {
      vi.mocked(savePrivateKey).mockImplementation(() => {
        throw new Error("EACCES");
      });

      await expect(runSetup(["--create"])).rejects.toThrow("process.exit(1)");

      const allOutput = [
        ...logSpy.mock.calls.map((c) => c[0]),
        ...errorSpy.mock.calls.map((c) => c[0]),
      ].join("\n");
      expect(allOutput).toContain("Couldn't save to");
    });
  });
});
