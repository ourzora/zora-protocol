import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./config.js", () => ({
  getPrivateKey: vi.fn(),
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: vi.fn(),
}));

vi.mock("viem", () => ({
  createPublicClient: vi.fn(),
  createWalletClient: vi.fn(),
  http: vi.fn(),
}));

vi.mock("viem/chains", () => ({
  base: { id: 8453, name: "Base" },
}));

import { getPrivateKey } from "./config.js";
import { privateKeyToAccount } from "viem/accounts";
import { createPublicClient, createWalletClient } from "viem";

const MOCK_KEY = "a".repeat(64);
const MOCK_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";

beforeEach(() => {
  delete process.env.ZORA_PRIVATE_KEY;
  vi.mocked(getPrivateKey).mockReturnValue(undefined);
  vi.mocked(privateKeyToAccount).mockReturnValue({
    address: MOCK_ADDRESS,
  } as never);
});

afterEach(() => {
  delete process.env.ZORA_PRIVATE_KEY;
  vi.restoreAllMocks();
});

describe("normalizeKey", () => {
  it("returns key as-is when it starts with 0x", async () => {
    const { normalizeKey } = await import("./wallet.js");
    expect(normalizeKey("0xabc")).toBe("0xabc");
  });

  it("prepends 0x when missing", async () => {
    const { normalizeKey } = await import("./wallet.js");
    expect(normalizeKey("abc")).toBe("0xabc");
  });
});

describe("resolveAccount", () => {
  it("exits when no key is configured", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    const { resolveAccount } = await import("./wallet.js");
    expect(() => resolveAccount()).toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("No wallet configured"),
    );

    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("uses ZORA_PRIVATE_KEY env var when set", async () => {
    process.env.ZORA_PRIVATE_KEY = MOCK_KEY;

    const { resolveAccount } = await import("./wallet.js");
    const account = resolveAccount();

    expect(privateKeyToAccount).toHaveBeenCalledWith(`0x${MOCK_KEY}`);
    expect(account.address).toBe(MOCK_ADDRESS);
  });

  it("falls back to file key when env is not set", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(`0x${MOCK_KEY}`);

    const { resolveAccount } = await import("./wallet.js");
    const account = resolveAccount();

    expect(privateKeyToAccount).toHaveBeenCalledWith(`0x${MOCK_KEY}`);
    expect(account.address).toBe(MOCK_ADDRESS);
  });

  it("exits with error on invalid private key", async () => {
    vi.mocked(getPrivateKey).mockReturnValue("bad-key");
    vi.mocked(privateKeyToAccount).mockImplementation(() => {
      throw new Error("invalid key");
    });
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    const { resolveAccount } = await import("./wallet.js");
    expect(() => resolveAccount()).toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid private key"),
    );

    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

describe("createClients", () => {
  it("creates public and wallet clients for base chain", async () => {
    const mockPublicClient = { type: "public" };
    const mockWalletClient = { type: "wallet" };
    vi.mocked(createPublicClient).mockReturnValue(mockPublicClient as never);
    vi.mocked(createWalletClient).mockReturnValue(mockWalletClient as never);

    const { createClients } = await import("./wallet.js");
    const account = { address: MOCK_ADDRESS } as never;
    const result = createClients(account);

    expect(result.publicClient).toBe(mockPublicClient);
    expect(result.walletClient).toBe(mockWalletClient);
    expect(createPublicClient).toHaveBeenCalled();
    expect(createWalletClient).toHaveBeenCalledWith(
      expect.objectContaining({ account }),
    );
  });
});
