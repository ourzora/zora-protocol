import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("./config.js", () => ({
  getWalletPath: vi.fn(() => "/home/u/.config/zora/wallet.json"),
}));
vi.mock("./prompt.js", () => ({ confirmOrDefault: vi.fn() }));

import {
  confirmAgentWalletOverwrite,
  confirmAgentAction,
} from "./agent-guard.js";
import { confirmOrDefault } from "./prompt.js";

const AGENT = {
  address: "0xAbC0000000000000000000000000000000000001",
  embeddedWalletAddress: "0xEeE0000000000000000000000000000000000001",
  smartWalletAddress: "0xd1373e4119dD2C4C23f11F9cDc97A464790acbC8",
  did: "did:privy:test",
  username: "keen_cedar_9807",
  profileUrl: "https://zora.co/@keen_cedar_9807",
  createdAt: "2026-06-10T00:00:00.000Z",
} as const;

let logSpy: ReturnType<typeof vi.spyOn>;
let errorSpy: ReturnType<typeof vi.spyOn>;
let exitSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  vi.clearAllMocks();
  logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
    throw new Error(`process.exit(${code})`);
  });
});

afterEach(() => {
  logSpy.mockRestore();
  errorSpy.mockRestore();
  exitSpy.mockRestore();
});

function allOutput(): string {
  return [
    ...logSpy.mock.calls.map((c) => c[0]),
    ...errorSpy.mock.calls.map((c) => c[0]),
  ].join("\n");
}

describe("confirmAgentWalletOverwrite", () => {
  it("refuses (exit 1) in non-interactive mode, without prompting", async () => {
    await expect(
      confirmAgentWalletOverwrite({
        json: false,
        nonInteractive: true,
        agent: AGENT,
      }),
    ).rejects.toThrow("process.exit(1)");
    expect(confirmOrDefault).not.toHaveBeenCalled();
    const out = allOutput();
    expect(out).toContain("keen_cedar_9807");
    expect(out).toContain(AGENT.smartWalletAddress);
  });

  it("refuses (exit 1) in --json mode too", async () => {
    await expect(
      confirmAgentWalletOverwrite({
        json: true,
        nonInteractive: true,
        agent: AGENT,
      }),
    ).rejects.toThrow("process.exit(1)");
    expect(confirmOrDefault).not.toHaveBeenCalled();
  });

  it("prompts interactively and returns when confirmed", async () => {
    vi.mocked(confirmOrDefault).mockResolvedValue(true);
    await expect(
      confirmAgentWalletOverwrite({
        json: false,
        nonInteractive: false,
        agent: AGENT,
      }),
    ).resolves.toBeUndefined();
    expect(confirmOrDefault).toHaveBeenCalledWith(
      expect.objectContaining({
        message: expect.stringContaining("keen_cedar_9807"),
        default: false,
      }),
      false,
    );
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("aborts (exit 0) when the interactive confirmation is declined", async () => {
    vi.mocked(confirmOrDefault).mockResolvedValue(false);
    await expect(
      confirmAgentWalletOverwrite({
        json: false,
        nonInteractive: false,
        agent: AGENT,
      }),
    ).rejects.toThrow("process.exit(0)");
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
  });
});

describe("confirmAgentAction", () => {
  const opts = { warning: "heads up", question: "Proceed?" };

  it("returns immediately when --force is set, without prompting", async () => {
    await expect(
      confirmAgentAction({ json: false, force: true, ...opts }),
    ).resolves.toBeUndefined();
    expect(confirmOrDefault).not.toHaveBeenCalled();
  });

  it("returns immediately in --json mode (headless), without prompting", async () => {
    await expect(
      confirmAgentAction({ json: true, ...opts }),
    ).resolves.toBeUndefined();
    expect(confirmOrDefault).not.toHaveBeenCalled();
  });

  it("prompts interactively and returns when confirmed", async () => {
    vi.mocked(confirmOrDefault).mockResolvedValue(true);
    await expect(
      confirmAgentAction({ json: false, ...opts }),
    ).resolves.toBeUndefined();
    expect(confirmOrDefault).toHaveBeenCalledWith(
      expect.objectContaining({ message: "Proceed?", default: false }),
      false,
    );
  });

  it("aborts (exit 0) when the interactive confirmation is declined", async () => {
    vi.mocked(confirmOrDefault).mockResolvedValue(false);
    await expect(confirmAgentAction({ json: false, ...opts })).rejects.toThrow(
      "process.exit(0)",
    );
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
  });
});
