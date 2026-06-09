import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";
import { agentCommand } from "./agent.js";
import { onboardAgent } from "../lib/agent/onboard.js";
import type { OnboardResult } from "../lib/agent/onboard.js";
import { getPrivateKey, savePrivateKey } from "../lib/config.js";
import { generatePrivateKey } from "viem/accounts";

vi.mock("../lib/agent/onboard.js", () => ({ onboardAgent: vi.fn() }));

vi.mock("../lib/privy.js", () => ({
  ZORA_PRIVY_APP_ID: "test-app-id",
  DEFAULT_SIWE_ORIGIN: "https://zora.com",
  DEFAULT_SIWE_CHAIN_ID: 8453,
}));

vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  savePrivateKey: vi.fn(),
  getWalletPath: vi.fn(() => "/home/u/.config/zora/wallet.json"),
}));

vi.mock("../lib/analytics.js", () => ({ track: vi.fn() }));

vi.mock("viem/accounts", () => ({
  generatePrivateKey: vi.fn(() => `0x${"1".repeat(64)}`),
}));

const SAVED_PK = `0x${"a".repeat(64)}` as const;
const GENERATED_PK = `0x${"1".repeat(64)}` as const;
const ONBOARD_RESULT: OnboardResult = {
  address: "0xAbC0000000000000000000000000000000000001",
  did: "did:privy:test123",
  accessToken: "header.payload.signature",
  username: "keen_cedar_9807",
  embedded: "0xEeE0000000000000000000000000000000000001",
  smartWallet: "0xd1373e4119dD2C4C23f11F9cDc97A464790acbC8",
  isNewUser: true,
};

function runAgent(args: string[]) {
  const program = createProgram(agentCommand);
  return program.parseAsync(["agent", ...args], { from: "user" });
}

function captureLog() {
  const calls: string[] = [];
  const spy = vi.spyOn(console, "log").mockImplementation((...args) => {
    calls.push(args.join(" "));
  });
  return { output: () => calls.join("\n"), restore: () => spy.mockRestore() };
}

describe("zora agent create", () => {
  const originalEnv = process.env.ZORA_PRIVATE_KEY;

  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
    vi.mocked(getPrivateKey).mockReturnValue(SAVED_PK);
    vi.mocked(onboardAgent).mockResolvedValue(ONBOARD_RESULT);
  });

  afterEach(() => {
    if (originalEnv === undefined) delete process.env.ZORA_PRIVATE_KEY;
    else process.env.ZORA_PRIVATE_KEY = originalEnv;
  });

  it("onboards with the saved wallet and outputs the result as JSON", async () => {
    const log = captureLog();
    await runAgent(["create", "--json"]);
    const parsed = JSON.parse(log.output());
    log.restore();

    expect(parsed).toMatchObject({
      address: ONBOARD_RESULT.address,
      username: "keen_cedar_9807",
      smartWallet: ONBOARD_RESULT.smartWallet,
      accessToken: ONBOARD_RESULT.accessToken,
      walletSource: "/home/u/.config/zora/wallet.json",
    });
    expect(onboardAgent).toHaveBeenCalledWith(
      expect.objectContaining({
        privateKey: SAVED_PK,
        appId: "test-app-id",
        origin: "https://zora.com",
        chainId: 8453,
      }),
    );
  });

  it("passes --rpc-url through", async () => {
    await runAgent(["create", "--json", "--rpc-url", "https://rpc.test"]);
    expect(onboardAgent).toHaveBeenCalledWith(
      expect.objectContaining({ rpcUrl: "https://rpc.test" }),
    );
  });

  it("uses --private-key over the saved wallet, and warns about shell-history exposure", async () => {
    const warn = vi.spyOn(console, "error").mockImplementation(() => {});
    await runAgent(["create", "--private-key", "b".repeat(64), "--json"]);
    expect(getPrivateKey).not.toHaveBeenCalled();
    expect(onboardAgent).toHaveBeenCalledWith(
      expect.objectContaining({ privateKey: `0x${"b".repeat(64)}` }),
    );
    // Assert before restoring — mockRestore() also clears the call history.
    expect(warn).toHaveBeenCalledWith(expect.stringContaining("shell history"));
    warn.mockRestore();
  });

  it("uses ZORA_PRIVATE_KEY when no flag is given", async () => {
    process.env.ZORA_PRIVATE_KEY = `0x${"c".repeat(64)}`;
    await runAgent(["create", "--json"]);
    expect(getPrivateKey).not.toHaveBeenCalled();
    expect(onboardAgent).toHaveBeenCalledWith(
      expect.objectContaining({ privateKey: `0x${"c".repeat(64)}` }),
    );
  });

  it("generates and persists a wallet when none is configured", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    await runAgent(["create", "--json"]);
    expect(generatePrivateKey).toHaveBeenCalled();
    expect(savePrivateKey).toHaveBeenCalledWith(GENERATED_PK);
    expect(onboardAgent).toHaveBeenCalledWith(
      expect.objectContaining({ privateKey: GENERATED_PK }),
    );
  });

  it("renders a human-readable summary without --json", async () => {
    const log = captureLog();
    await runAgent(["create"]);
    const output = log.output();
    log.restore();
    expect(output).toContain("keen_cedar_9807");
    expect(output).toContain(ONBOARD_RESULT.smartWallet);
    expect(output).toContain(ONBOARD_RESULT.accessToken);
  });

  it("exits with an error when onboarding fails", async () => {
    vi.mocked(onboardAgent).mockRejectedValue(new Error("boom"));
    await expect(runAgent(["create"])).rejects.toThrow("process.exit(1)");
  });

  it("rejects an invalid --private-key before onboarding", async () => {
    await expect(
      runAgent(["create", "--private-key", "not-a-key"]),
    ).rejects.toThrow("process.exit(1)");
    expect(onboardAgent).not.toHaveBeenCalled();
  });

  it("rejects an invalid --chain-id", async () => {
    await expect(runAgent(["create", "--chain-id", "abc"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(onboardAgent).not.toHaveBeenCalled();
  });

  it("rejects an invalid ZORA_PRIVATE_KEY", async () => {
    process.env.ZORA_PRIVATE_KEY = "bad";
    await expect(runAgent(["create"])).rejects.toThrow("process.exit(1)");
    expect(onboardAgent).not.toHaveBeenCalled();
  });

  it("exits with a clear error when the saved wallet is corrupted", async () => {
    vi.mocked(getPrivateKey).mockReturnValue("not-a-valid-key");
    await expect(runAgent(["create"])).rejects.toThrow("process.exit(1)");
    expect(onboardAgent).not.toHaveBeenCalled();
  });
});
