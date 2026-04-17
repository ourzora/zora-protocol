import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  savePrivateKey: vi.fn(),
  getWalletPath: vi.fn(() => "/tmp/.zora/wallet.json"),
  getApiKey: vi.fn(),
  getEnvApiKey: vi.fn(),
  saveApiKey: vi.fn(),
  getConfigPath: vi.fn(() => "/tmp/.zora/config.json"),
}));

vi.mock("viem/accounts", () => ({
  generatePrivateKey: vi.fn(),
  privateKeyToAccount: vi.fn(),
}));

vi.mock("../lib/prompt.js", () => ({
  selectOrDefault: vi.fn(),
  passwordOrFail: vi.fn(),
  confirmOrDefault: vi.fn(),
  passwordOrSkip: vi.fn(),
}));

import {
  getPrivateKey,
  savePrivateKey,
  getWalletPath,
  getApiKey,
  getEnvApiKey,
  saveApiKey,
  getConfigPath,
} from "../lib/config.js";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import {
  selectOrDefault,
  passwordOrFail,
  confirmOrDefault,
  passwordOrSkip,
} from "../lib/prompt.js";
import { setupCommand } from "./setup.js";

const MOCK_KEY = ("0x" + "a".repeat(64)) as `0x${string}`;
const MOCK_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";

async function runSetup(args: string[] = []) {
  const program = createProgram(setupCommand);
  await program.parseAsync(["setup", ...args], { from: "user" });
}

describe("setup command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.resetAllMocks();
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });
    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    vi.mocked(generatePrivateKey).mockReturnValue(MOCK_KEY);
    vi.mocked(privateKeyToAccount).mockReturnValue({
      address: MOCK_ADDRESS,
    } as ReturnType<typeof privateKeyToAccount>);
    vi.mocked(getApiKey).mockReturnValue(undefined);
    vi.mocked(getEnvApiKey).mockReturnValue(undefined);
    vi.mocked(getWalletPath).mockReturnValue("/tmp/.zora/wallet.json");
    vi.mocked(getConfigPath).mockReturnValue("/tmp/.zora/config.json");
    vi.mocked(passwordOrSkip).mockResolvedValue("");
    delete process.env.ZORA_PRIVATE_KEY;
  });

  afterEach(() => {
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
    delete process.env.ZORA_PRIVATE_KEY;
  });

  describe("step indicators", () => {
    it("prints [1/3], [2/3], [3/3] step indicators", async () => {
      await runSetup(["--create"]);

      const allOutput = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(allOutput).toContain("[1/3]");
      expect(allOutput).toContain("[2/3]");
      expect(allOutput).toContain("[3/3]");
    });
  });

  describe("--create flag (no prompt)", () => {
    it("generates a key, saves it, and prints success", async () => {
      await runSetup(["--create"]);

      expect(generatePrivateKey).toHaveBeenCalled();
      expect(savePrivateKey).toHaveBeenCalledWith(MOCK_KEY);
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("\u2713 Wallet created"),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining(MOCK_ADDRESS),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("/tmp/.zora/wallet.json"),
      );
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
        expect.objectContaining({
          message: "How do you want to set up your wallet?",
        }),
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
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("\u2713 Wallet imported"),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining(MOCK_ADDRESS),
      );
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
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Not a valid private key"),
      );
      expect(savePrivateKey).toHaveBeenCalledWith("a".repeat(64));
    });

    it("trims whitespace from pasted key", async () => {
      vi.mocked(selectOrDefault).mockResolvedValue("import" as never);
      vi.mocked(passwordOrFail).mockResolvedValue("  " + "a".repeat(64) + "  ");

      await runSetup([]);

      expect(savePrivateKey).toHaveBeenCalledWith("a".repeat(64));
    });
  });

  describe("existing wallet (re-runnable)", () => {
    it("prompts to overwrite when wallet exists", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
      vi.mocked(confirmOrDefault).mockResolvedValue(false);

      await runSetup(["--create"]);

      expect(confirmOrDefault).toHaveBeenCalledWith(
        expect.objectContaining({
          message: "Overwrite wallet configuration?",
        }),
        false,
      );
    });

    it("skips wallet when user declines overwrite", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
      vi.mocked(confirmOrDefault).mockResolvedValue(false);

      await runSetup(["--create"]);

      expect(savePrivateKey).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Keeping existing wallet"),
      );
    });

    it("proceeds with creation when user accepts overwrite", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
      vi.mocked(confirmOrDefault).mockResolvedValue(true);
      const newKey = ("0x" + "b".repeat(64)) as `0x${string}`;
      vi.mocked(generatePrivateKey).mockReturnValue(newKey);

      await runSetup(["--create"]);

      expect(savePrivateKey).toHaveBeenCalledWith(newKey);
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
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("ZORA_PRIVATE_KEY"),
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining(MOCK_ADDRESS),
      );
    });

    it("uses env var with 0x prefix", async () => {
      process.env.ZORA_PRIVATE_KEY = "0x" + "a".repeat(64);

      await runSetup([]);

      expect(savePrivateKey).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("ZORA_PRIVATE_KEY"),
      );
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
        throw new Error(
          "/home/user/.config/zora/wallet.json: Unexpected token",
        );
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
        throw new Error(
          "/home/user/.config/zora/wallet.json: Unexpected token",
        );
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

  describe("API key step", () => {
    it("saves API key when user provides one", async () => {
      vi.mocked(passwordOrSkip).mockResolvedValue("my-api-key");

      await runSetup(["--create"]);

      expect(saveApiKey).toHaveBeenCalledWith("my-api-key");
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("API key saved"),
      );
    });

    it("skips API key when user presses Enter", async () => {
      vi.mocked(passwordOrSkip).mockResolvedValue("");

      await runSetup(["--create"]);

      expect(saveApiKey).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Skipped API key"),
      );
    });

    it("detects ZORA_API_KEY env var override", async () => {
      vi.mocked(getEnvApiKey).mockReturnValue("env-key");

      await runSetup(["--create"]);

      expect(saveApiKey).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("ZORA_API_KEY environment variable"),
      );
    });

    it("prompts to overwrite existing API key", async () => {
      vi.mocked(getApiKey).mockReturnValue("existing-key");
      vi.mocked(confirmOrDefault)
        .mockResolvedValueOnce(true) // wallet overwrite prompt (if wallet exists)
        .mockResolvedValueOnce(false); // API key overwrite

      await runSetup(["--create"]);

      expect(confirmOrDefault).toHaveBeenCalledWith(
        expect.objectContaining({ message: "Overwrite API key?" }),
        false,
      );
      expect(saveApiKey).not.toHaveBeenCalled();
    });
  });

  describe("--yes mode", () => {
    it("creates wallet and skips API key in non-interactive mode", async () => {
      await runSetup(["--create", "--yes"]);

      expect(savePrivateKey).toHaveBeenCalledWith(MOCK_KEY);
      expect(saveApiKey).not.toHaveBeenCalled();
    });

    it("skips wallet when existing and --yes without --force", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);

      await runSetup(["--create", "--yes"]);

      expect(savePrivateKey).not.toHaveBeenCalled();
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Keeping existing wallet"),
      );
    });

    it("overwrites wallet with --yes --force", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
      const newKey = ("0x" + "b".repeat(64)) as `0x${string}`;
      vi.mocked(generatePrivateKey).mockReturnValue(newKey);

      await runSetup(["--create", "--yes", "--force"]);

      expect(savePrivateKey).toHaveBeenCalledWith(newKey);
    });
  });

  describe("--json output", () => {
    it("outputs combined JSON structure", async () => {
      await runSetup(["--json", "--create", "--yes"]);

      const jsonCalls = logSpy.mock.calls
        .map((c) => c[0])
        .filter((s) => typeof s === "string");
      const jsonOutput = jsonCalls.find((s) => {
        try {
          JSON.parse(s);
          return true;
        } catch {
          return false;
        }
      });
      expect(jsonOutput).toBeDefined();
      const parsed = JSON.parse(jsonOutput!);
      expect(parsed).toHaveProperty("wallet");
      expect(parsed).toHaveProperty("apiKey");
      expect(parsed.wallet.action).toBe("created");
      expect(parsed.apiKey).toBe("skipped");
    });
  });
});
