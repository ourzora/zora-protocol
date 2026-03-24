import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./config.js", () => ({
  getPrivateKey: vi.fn(),
}));

vi.mock("@zoralabs/coins-sdk", () => ({
  apiPost: vi.fn(),
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: vi.fn(),
}));

vi.mock("viem", () => ({
  createPublicClient: vi.fn(),
  createWalletClient: vi.fn(),
  custom: vi.fn((transport) => transport),
}));

vi.mock("viem/chains", () => ({
  base: { id: 8453, name: "Base" },
}));

vi.mock("./output.js", () => ({
  outputErrorAndExit: vi.fn((json: boolean, message: string) => {
    if (json) {
      console.log(JSON.stringify({ error: message }));
    } else {
      console.error(`Error: ${message}`);
    }
    process.exit(1);
  }),
}));

import { getPrivateKey } from "./config.js";
import { apiPost } from "@zoralabs/coins-sdk";
import { privateKeyToAccount } from "viem/accounts";
import { createPublicClient, createWalletClient, custom } from "viem";
import {
  normalizeKey,
  resolveAccount,
  createClients,
  createCliRpcTransport,
} from "./wallet.js";

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
    expect(normalizeKey("0xabc")).toBe("0xabc");
  });

  it("prepends 0x when missing", async () => {
    expect(normalizeKey("abc")).toBe("0xabc");
  });
});

describe("resolveAccount", () => {
  it("exits when no key is configured", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    expect(() => resolveAccount()).toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("No wallet configured"),
    );

    errorSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("uses ZORA_PRIVATE_KEY env var when set", async () => {
    process.env.ZORA_PRIVATE_KEY = MOCK_KEY;

    const account = resolveAccount();

    expect(privateKeyToAccount).toHaveBeenCalledWith(`0x${MOCK_KEY}`);
    expect(account.address).toBe(MOCK_ADDRESS);
  });

  it("falls back to file key when env is not set", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(`0x${MOCK_KEY}`);

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

    const account = { address: MOCK_ADDRESS } as never;
    const result = createClients(account);

    expect(result.publicClient).toBe(mockPublicClient);
    expect(result.walletClient).toBe(mockWalletClient);
    expect(custom).toHaveBeenCalledWith(
      expect.objectContaining({
        request: expect.any(Function),
      }),
    );
    expect(createPublicClient).toHaveBeenCalledWith(
      expect.objectContaining({
        transport: expect.any(Object),
      }),
    );
    expect(createWalletClient).toHaveBeenCalledWith(
      expect.objectContaining({
        account,
        transport: expect.any(Object),
      }),
    );

    expect(vi.mocked(createWalletClient).mock.calls[0]?.[0].transport).toBe(
      vi.mocked(createPublicClient).mock.calls[0]?.[0].transport,
    );
  });
});

describe("createCliRpcTransport", () => {
  it("routes rpc requests through /cli-rpc and unwraps result payloads", async () => {
    vi.mocked(apiPost).mockResolvedValue({
      data: { result: "0x123" },
      error: undefined,
    } as never);

    const transport = createCliRpcTransport();

    const result = await transport.request({
      method: "eth_blockNumber",
      params: [],
    });

    expect(apiPost).toHaveBeenCalledWith("/cli-rpc", {
      chainId: 8453,
      method: "eth_blockNumber",
      params: [],
    });
    expect(result).toBe("0x123");
  });

  it("passes custom chainId to apiPost", async () => {
    vi.mocked(apiPost).mockResolvedValue({
      data: { result: "0x1" },
      error: undefined,
    } as never);

    const transport = createCliRpcTransport(1);

    await transport.request({
      method: "eth_chainId",
      params: [],
    });

    expect(apiPost).toHaveBeenCalledWith("/cli-rpc", {
      chainId: 1,
      method: "eth_chainId",
      params: [],
    });
  });

  it("defaults chainId to base (8453) when not specified", async () => {
    vi.mocked(apiPost).mockResolvedValue({
      data: { result: "0x1" },
      error: undefined,
    } as never);

    const transport = createCliRpcTransport();

    await transport.request({
      method: "eth_blockNumber",
      params: [],
    });

    expect(apiPost).toHaveBeenCalledWith("/cli-rpc", {
      chainId: 8453,
      method: "eth_blockNumber",
      params: [],
    });
  });

  it("wraps network errors with consistent formatting", async () => {
    vi.mocked(apiPost).mockRejectedValue(new Error("fetch failed"));

    const transport = createCliRpcTransport();

    await expect(
      transport.request({
        method: "eth_blockNumber",
        params: [],
      }),
    ).rejects.toThrow("CLI RPC request failed: fetch failed");
  });

  it("wraps non-Error network exceptions with consistent formatting", async () => {
    vi.mocked(apiPost).mockRejectedValue("timeout");

    const transport = createCliRpcTransport();

    await expect(
      transport.request({
        method: "eth_blockNumber",
        params: [],
      }),
    ).rejects.toThrow("CLI RPC request failed: timeout");
  });

  it("throws when the sdk returns an error", async () => {
    vi.mocked(apiPost).mockResolvedValue({
      data: undefined,
      error: { message: "rate limited" },
    } as never);

    const transport = createCliRpcTransport();

    await expect(
      transport.request({
        method: "eth_chainId",
        params: [],
      }),
    ).rejects.toThrow("CLI RPC request failed: rate limited");
  });
});
