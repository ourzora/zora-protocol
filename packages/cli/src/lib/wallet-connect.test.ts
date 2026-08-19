import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import type { Address } from "viem";

vi.mock("./config.js", () => ({
  getPrivateKey: vi.fn(),
  saveConnectedWallet: vi.fn(),
  getWalletPath: vi.fn(() => "/tmp/.zora/wallet.json"),
  peekAgentWallet: vi.fn(),
}));

vi.mock("./prompt.js", () => ({
  passwordOrFail: vi.fn(),
  confirmOrDefault: vi.fn(),
}));

vi.mock("./client/public.js", () => ({
  createPublicClient: vi.fn(() => ({})),
}));

vi.mock("./agent-guard.js", () => ({
  confirmAgentWalletOverwrite: vi.fn(),
}));

// Keep the real error classes; only stub the network-touching resolver.
vi.mock("./account/connect.js", async (importActual) => {
  const actual = await importActual<typeof import("./account/connect.js")>();
  return { ...actual, resolveConnection: vi.fn() };
});

import {
  getPrivateKey,
  saveConnectedWallet,
  peekAgentWallet,
} from "./config.js";
import { passwordOrFail, confirmOrDefault } from "./prompt.js";
import { confirmAgentWalletOverwrite } from "./agent-guard.js";
import {
  NoSmartWalletFoundError,
  NotSmartWalletOwnerError,
  resolveConnection,
} from "./account/connect.js";
import { connectWallet } from "./wallet-connect.js";

const VALID_KEY = "0x" + "a".repeat(64);
const OWNER = "0x152713CF688ABBE046D843f03d213b0F41B172Af" as Address;
const SMART_WALLET = "0x473de669566008551Ce71322E52ebD70c2e44123" as Address;

const discovered = {
  ownerAddress: OWNER,
  smartWalletAddress: SMART_WALLET,
  discovered: true as const,
};

describe("connectWallet", () => {
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
    vi.mocked(peekAgentWallet).mockReturnValue(undefined);
    vi.mocked(resolveConnection).mockResolvedValue(discovered);
    delete process.env.ZORA_PRIVATE_KEY;
  });

  afterEach(() => {
    logSpy.mockRestore();
    errorSpy.mockRestore();
    exitSpy.mockRestore();
    vi.clearAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
  });

  it("connects and saves when the key resolves to a smart wallet", async () => {
    const result = await connectWallet({
      json: false,
      nonInteractive: true,
      key: VALID_KEY,
    });

    expect(result).toEqual({
      ownerAddress: OWNER,
      smartWalletAddress: SMART_WALLET,
      discovered: true,
      path: "/tmp/.zora/wallet.json",
    });
    expect(saveConnectedWallet).toHaveBeenCalledWith(VALID_KEY, SMART_WALLET);
  });

  it("prompts for the key when none is supplied", async () => {
    vi.mocked(passwordOrFail).mockResolvedValue(VALID_KEY);

    await connectWallet({ json: false, nonInteractive: false });

    expect(passwordOrFail).toHaveBeenCalled();
    expect(saveConnectedWallet).toHaveBeenCalledWith(VALID_KEY, SMART_WALLET);
  });

  it("rejects a malformed key without touching the chain", async () => {
    await expect(
      connectWallet({ json: false, nonInteractive: true, key: "nope" }),
    ).rejects.toThrow(/process.exit/);
    expect(resolveConnection).not.toHaveBeenCalled();
    expect(saveConnectedWallet).not.toHaveBeenCalled();
  });

  it("rejects an invalid --smart-wallet address", async () => {
    await expect(
      connectWallet({
        json: false,
        nonInteractive: true,
        key: VALID_KEY,
        smartWallet: "0xnotanaddress",
      }),
    ).rejects.toThrow(/process.exit/);
    expect(saveConnectedWallet).not.toHaveBeenCalled();
  });

  it("refuses to overwrite an existing wallet non-interactively without --force", async () => {
    vi.mocked(getPrivateKey).mockReturnValue("0x" + "b".repeat(64));

    await expect(
      connectWallet({ json: false, nonInteractive: true, key: VALID_KEY }),
    ).rejects.toThrow(/process.exit/);
    expect(saveConnectedWallet).not.toHaveBeenCalled();
  });

  it("overwrites an existing wallet when --force is given", async () => {
    vi.mocked(getPrivateKey).mockReturnValue("0x" + "b".repeat(64));

    await connectWallet({
      json: false,
      nonInteractive: true,
      key: VALID_KEY,
      force: true,
    });

    expect(saveConnectedWallet).toHaveBeenCalledWith(VALID_KEY, SMART_WALLET);
  });

  it("guards an agent wallet via confirmAgentWalletOverwrite", async () => {
    vi.mocked(peekAgentWallet).mockReturnValue({
      username: "agent",
      address: OWNER,
      embeddedWalletAddress: OWNER,
      smartWalletAddress: SMART_WALLET,
      did: "did:privy:x",
      profileUrl: "https://zora.co/@agent",
      createdAt: "2026-01-01T00:00:00.000Z",
    });

    await connectWallet({
      json: false,
      nonInteractive: false,
      key: VALID_KEY,
      force: true,
    });

    expect(confirmAgentWalletOverwrite).toHaveBeenCalled();
  });

  it("surfaces a friendly error and does not save when no smart wallet is found", async () => {
    vi.mocked(resolveConnection).mockRejectedValue(
      new NoSmartWalletFoundError(OWNER),
    );

    await expect(
      connectWallet({ json: false, nonInteractive: true, key: VALID_KEY }),
    ).rejects.toThrow(/process.exit/);
    expect(saveConnectedWallet).not.toHaveBeenCalled();
  });

  it("surfaces a friendly error when the key isn't an owner", async () => {
    vi.mocked(resolveConnection).mockRejectedValue(
      new NotSmartWalletOwnerError(OWNER, SMART_WALLET),
    );

    await expect(
      connectWallet({
        json: false,
        nonInteractive: true,
        key: VALID_KEY,
        smartWallet: SMART_WALLET,
      }),
    ).rejects.toThrow(/process.exit/);
    expect(saveConnectedWallet).not.toHaveBeenCalled();
  });
});
