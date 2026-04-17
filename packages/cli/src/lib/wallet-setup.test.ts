import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

vi.mock("./config.js", () => ({
  getPrivateKey: vi.fn(),
  savePrivateKey: vi.fn(),
  getWalletPath: vi.fn(() => "/tmp/.zora/wallet.json"),
}));

vi.mock("viem/accounts", () => ({
  generatePrivateKey: vi.fn(),
  privateKeyToAccount: vi.fn(),
}));

vi.mock("./prompt.js", () => ({
  selectOrDefault: vi.fn(),
  passwordOrFail: vi.fn(),
  confirmOrDefault: vi.fn(),
}));

import { getPrivateKey, savePrivateKey } from "./config.js";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { selectOrDefault, confirmOrDefault } from "./prompt.js";
import { configureWallet } from "./wallet-setup.js";

const MOCK_KEY = ("0x" + "a".repeat(64)) as `0x${string}`;
const MOCK_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";

describe("configureWallet", () => {
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
    vi.mocked(privateKeyToAccount).mockReturnValue({
      address: MOCK_ADDRESS,
    } as ReturnType<typeof privateKeyToAccount>);
    delete process.env.ZORA_PRIVATE_KEY;
  });

  afterEach(() => {
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
    vi.clearAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
  });

  describe("env var handling", () => {
    it("returns env_detected when ZORA_PRIVATE_KEY is set", async () => {
      process.env.ZORA_PRIVATE_KEY = "a".repeat(64);

      const result = await configureWallet({
        json: false,
        nonInteractive: false,
      });

      expect(result).toEqual({
        action: "env_detected",
        address: MOCK_ADDRESS,
      });
      expect(savePrivateKey).not.toHaveBeenCalled();
    });

    it("exits on invalid env var", async () => {
      process.env.ZORA_PRIVATE_KEY = "bad";

      await expect(
        configureWallet({ json: false, nonInteractive: false }),
      ).rejects.toThrow("process.exit(1)");
    });
  });

  describe("promptOverwrite mode", () => {
    it("prompts to overwrite when wallet exists and promptOverwrite is true", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);
      vi.mocked(confirmOrDefault).mockResolvedValue(false);

      const result = await configureWallet({
        json: false,
        nonInteractive: false,
        create: true,
        promptOverwrite: true,
      });

      expect(result.action).toBe("skipped");
      expect(result.address).toBe(MOCK_ADDRESS);
      expect("warning" in result && result.warning).toContain(
        "Wallet already configured",
      );
      expect(confirmOrDefault).toHaveBeenCalled();
    });

    it("skips automatically in non-interactive + promptOverwrite mode", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);

      const result = await configureWallet({
        json: false,
        nonInteractive: true,
        create: true,
        promptOverwrite: true,
      });

      expect(result.action).toBe("skipped");
      expect(result.address).toBe(MOCK_ADDRESS);
      expect("warning" in result && result.warning).toContain(
        "Wallet already configured",
      );
      expect(confirmOrDefault).not.toHaveBeenCalled();
    });

    it("errors when wallet exists without --force and promptOverwrite is false", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);

      await expect(
        configureWallet({
          json: false,
          nonInteractive: false,
          create: true,
          promptOverwrite: false,
        }),
      ).rejects.toThrow("process.exit(1)");
    });
  });

  describe("force flag", () => {
    it("skips existing wallet check when force is true", async () => {
      vi.mocked(getPrivateKey).mockReturnValue(MOCK_KEY);

      const result = await configureWallet({
        json: false,
        nonInteractive: false,
        create: true,
        force: true,
      });

      expect(result.action).toBe("created");
      expect(getPrivateKey).not.toHaveBeenCalled();
    });
  });

  describe("create flow", () => {
    it("generates and saves a new key", async () => {
      const result = await configureWallet({
        json: false,
        nonInteractive: false,
        create: true,
      });

      expect(result).toEqual({
        action: "created",
        address: MOCK_ADDRESS,
        path: "/tmp/.zora/wallet.json",
      });
      expect(savePrivateKey).toHaveBeenCalledWith(MOCK_KEY);
    });
  });

  describe("import flow", () => {
    it("uses interactive select when create is not specified", async () => {
      vi.mocked(selectOrDefault).mockResolvedValue("create" as never);

      await configureWallet({
        json: false,
        nonInteractive: false,
      });

      expect(selectOrDefault).toHaveBeenCalledWith(
        expect.objectContaining({
          message: "How do you want to set up your wallet?",
        }),
        false,
      );
    });
  });
});
