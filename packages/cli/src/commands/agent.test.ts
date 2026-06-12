import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";
import { agentCommand } from "./agent.js";
import { onboardAgent } from "../lib/agent/onboard.js";
import type { OnboardResult } from "../lib/agent/onboard.js";
import {
  getPrivateKey,
  savePrivateKey,
  saveAgentWallet,
  peekAgentWallet,
} from "../lib/config.js";
import { generatePrivateKey } from "viem/accounts";
import { confirmAgentAction } from "../lib/agent-guard.js";
import {
  createPrivyAccount,
  sendEmailCode,
  linkEmailWithCode,
  hasLinkedEmail,
} from "../lib/privy.js";
import { inputOrFail } from "../lib/prompt.js";
import { updateAgentProfile } from "../lib/agent/update-profile.js";

vi.mock("../lib/agent/onboard.js", () => ({ onboardAgent: vi.fn() }));

vi.mock("../lib/privy.js", () => ({
  ZORA_PRIVY_APP_ID: "test-app-id",
  DEFAULT_SIWE_ORIGIN: "https://zora.com",
  DEFAULT_SIWE_CHAIN_ID: 8453,
  createPrivyAccount: vi.fn(),
  sendEmailCode: vi.fn(),
  linkEmailWithCode: vi.fn(),
  hasLinkedEmail: vi.fn(),
}));

vi.mock("../lib/prompt.js", () => ({ inputOrFail: vi.fn() }));

vi.mock("../lib/config.js", () => ({
  getPrivateKey: vi.fn(),
  savePrivateKey: vi.fn(),
  saveAgentWallet: vi.fn(),
  peekAgentWallet: vi.fn(),
  getWalletPath: vi.fn(() => "/home/u/.config/zora/wallet.json"),
}));

// The guard's own behavior is unit-tested in agent-guard.test.ts; here we only
// assert the commands wire it up correctly, so stub it to a no-op (proceed).
vi.mock("../lib/agent-guard.js", () => ({ confirmAgentAction: vi.fn() }));

vi.mock("../lib/agent/update-profile.js", () => ({
  updateAgentProfile: vi.fn(),
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
  dryRun: false,
  profileUrl: "https://zora.co/@keen_cedar_9807",
  coin: {
    hash: "0xco001",
    sponsored: true,
    simulation: "ExecutionResult",
    url: "https://zora.co/@keen_cedar_9807/creator-coin",
  },
  post: {
    hash: "0xp0001",
    greeting: "gm frens",
    ticker: "GMFRENS",
    sponsored: true,
    simulation: "ExecutionResult",
    imageUri: "ipfs://image",
    contractUri: "ipfs://meta",
    coinAddress: "0x1f6835c4996fad83c8af2afa00056adf9234fe72",
    url: "https://zora.co/coin/base:0x1f6835c4996fad83c8af2afa00056adf9234fe72",
  },
};

const AGENT_INFO = {
  address: "0xAbC0000000000000000000000000000000000001",
  embeddedWalletAddress: "0xEeE0000000000000000000000000000000000001",
  smartWalletAddress: "0xd1373e4119dD2C4C23f11F9cDc97A464790acbC8",
  did: "did:privy:test123",
  username: "keen_cedar_9807",
  profileUrl: "https://zora.co/@keen_cedar_9807",
  createdAt: "2026-06-10T00:00:00.000Z",
} as const;

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

  it("runs the full onboarding with the saved wallet and outputs JSON", async () => {
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
      walletPath: "/home/u/.config/zora/wallet.json",
      savedToWallet: true,
    });
    expect(onboardAgent).toHaveBeenCalledWith(
      expect.objectContaining({
        privateKey: SAVED_PK,
        appId: "test-app-id",
        origin: "https://zora.com",
        chainId: 8453,
        dryRun: false,
        skipCoin: false,
        skipPost: false,
      }),
    );
  });

  it("passes --dry-run, --skip-coin, --skip-post and --rpc-url through", async () => {
    await runAgent([
      "create",
      "--json",
      "--dry-run",
      "--skip-coin",
      "--skip-post",
      "--rpc-url",
      "https://rpc.test",
    ]);
    expect(onboardAgent).toHaveBeenCalledWith(
      expect.objectContaining({
        dryRun: true,
        skipCoin: true,
        skipPost: true,
        rpcUrl: "https://rpc.test",
      }),
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
    expect(output).toContain("gm frens");
    expect(output).toContain("Links:");
    expect(output).toContain(
      "https://zora.co/coin/base:0x1f6835c4996fad83c8af2afa00056adf9234fe72",
    );
  });

  it("still prints the profile link when the first post step failed", async () => {
    vi.mocked(onboardAgent).mockResolvedValue({
      ...ONBOARD_RESULT,
      post: undefined,
      postError: "post boom",
    });
    const log = captureLog();
    await runAgent(["create"]);
    const output = log.output();
    log.restore();
    // The account was created, so its profile link must still be reported.
    expect(output).toContain("https://zora.co/@keen_cedar_9807");
    expect(output).toContain("First post:   failed — post boom");
    expect(output).toContain("account was created");
  });

  it("includes profileUrl and postError in --json when the post step failed", async () => {
    vi.mocked(onboardAgent).mockResolvedValue({
      ...ONBOARD_RESULT,
      post: undefined,
      postError: "post boom",
    });
    const log = captureLog();
    await runAgent(["create", "--json"]);
    const parsed = JSON.parse(log.output());
    log.restore();
    expect(parsed.profileUrl).toBe("https://zora.co/@keen_cedar_9807");
    expect(parsed.postError).toBe("post boom");
  });

  it("notes the profile fallback when the post coin address is unresolved", async () => {
    vi.mocked(onboardAgent).mockResolvedValue({
      ...ONBOARD_RESULT,
      post: {
        ...ONBOARD_RESULT.post!,
        coinAddress: undefined,
        url: ONBOARD_RESULT.profileUrl,
      },
    });
    const log = captureLog();
    await runAgent(["create"]);
    const output = log.output();
    log.restore();
    expect(output).toContain("First post:   https://zora.co/@keen_cedar_9807");
    expect(output).toContain("shown on the profile");
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

  it("saves the full agent identity to the wallet file (saved-wallet key)", async () => {
    await runAgent(["create", "--json"]);
    expect(saveAgentWallet).toHaveBeenCalledWith({
      address: ONBOARD_RESULT.address,
      embeddedWalletAddress: ONBOARD_RESULT.embedded,
      smartWalletAddress: ONBOARD_RESULT.smartWallet,
      did: ONBOARD_RESULT.did,
      username: ONBOARD_RESULT.username,
      profileUrl: ONBOARD_RESULT.profileUrl,
      createdAt: expect.any(String),
    });
  });

  it("saves the agent identity for a freshly generated wallet", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    await runAgent(["create", "--json"]);
    expect(savePrivateKey).toHaveBeenCalledWith(GENERATED_PK);
    expect(saveAgentWallet).toHaveBeenCalledWith(
      expect.objectContaining({
        address: ONBOARD_RESULT.address,
        embeddedWalletAddress: ONBOARD_RESULT.embedded,
        smartWalletAddress: ONBOARD_RESULT.smartWallet,
      }),
    );
  });

  it("persists the agent identity even with --dry-run", async () => {
    vi.mocked(onboardAgent).mockResolvedValue({
      ...ONBOARD_RESULT,
      dryRun: true,
    });
    await runAgent(["create", "--dry-run", "--json"]);
    expect(saveAgentWallet).toHaveBeenCalledWith(
      expect.objectContaining({
        smartWalletAddress: ONBOARD_RESULT.smartWallet,
        embeddedWalletAddress: ONBOARD_RESULT.embedded,
      }),
    );
  });

  it("does not touch the wallet file when the key comes from --private-key", async () => {
    const warn = vi.spyOn(console, "error").mockImplementation(() => {});
    await runAgent(["create", "--private-key", "b".repeat(64), "--json"]);
    expect(saveAgentWallet).not.toHaveBeenCalled();
    warn.mockRestore();
  });

  it("does not touch the wallet file when the key comes from ZORA_PRIVATE_KEY", async () => {
    process.env.ZORA_PRIVATE_KEY = `0x${"c".repeat(64)}`;
    await runAgent(["create", "--json"]);
    expect(saveAgentWallet).not.toHaveBeenCalled();
  });

  it("warns but still completes when saving the identity fails", async () => {
    vi.mocked(saveAgentWallet).mockImplementation(() => {
      throw new Error("EACCES: permission denied");
    });
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const log = captureLog();
    // Resolves (the command does not exit non-zero) — the agent already exists.
    await runAgent(["create", "--json"]);
    const parsed = JSON.parse(log.output());
    log.restore();
    // Assert before restoring — mockRestore() also clears the call history.
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("couldn't save its details"),
    );
    expect(parsed.savedToWallet).toBe(false);
    errorSpy.mockRestore();
  });

  describe("re-run guard (existing agent)", () => {
    it("confirms before re-minting when the wallet already owns an agent", async () => {
      vi.mocked(peekAgentWallet).mockReturnValue(AGENT_INFO);
      await runAgent(["create", "--json"]);
      expect(confirmAgentAction).toHaveBeenCalledWith(
        expect.objectContaining({
          question: expect.stringContaining("keen_cedar_9807"),
        }),
      );
      // The guard stub proceeds, so onboarding still runs.
      expect(onboardAgent).toHaveBeenCalled();
    });

    it("does not confirm on a first run (no existing agent)", async () => {
      vi.mocked(peekAgentWallet).mockReturnValue(undefined);
      await runAgent(["create", "--json"]);
      expect(confirmAgentAction).not.toHaveBeenCalled();
    });

    it("does not confirm under --dry-run (nothing is minted)", async () => {
      vi.mocked(peekAgentWallet).mockReturnValue(AGENT_INFO);
      await runAgent(["create", "--dry-run", "--json"]);
      expect(confirmAgentAction).not.toHaveBeenCalled();
    });

    it("forwards --force so the guard can skip the prompt", async () => {
      vi.mocked(peekAgentWallet).mockReturnValue(AGENT_INFO);
      await runAgent(["create", "--force", "--json"]);
      expect(confirmAgentAction).toHaveBeenCalledWith(
        expect.objectContaining({ force: true }),
      );
    });
  });
});

describe("zora agent update", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
    vi.mocked(getPrivateKey).mockReturnValue(SAVED_PK);
    vi.mocked(peekAgentWallet).mockReturnValue(AGENT_INFO);
    vi.mocked(createPrivyAccount).mockResolvedValue({
      accessToken: "header.payload.signature",
      address: AGENT_INFO.address,
      did: AGENT_INFO.did,
      isNewUser: false,
      linkedAccounts: [],
    } as never);
    vi.mocked(updateAgentProfile).mockResolvedValue({
      username: "fresh_handle",
      avatarUri: undefined,
    } as never);
  });

  it("confirms before changing an existing agent's username", async () => {
    await runAgent(["update", "--username", "fresh_handle", "--json"]);
    expect(confirmAgentAction).toHaveBeenCalledWith(
      expect.objectContaining({
        question: expect.stringContaining("keen_cedar_9807"),
      }),
    );
    expect(updateAgentProfile).toHaveBeenCalled();
  });

  it("forwards --force so the rename confirmation can be skipped", async () => {
    await runAgent([
      "update",
      "--username",
      "fresh_handle",
      "--force",
      "--json",
    ]);
    expect(confirmAgentAction).toHaveBeenCalledWith(
      expect.objectContaining({ force: true }),
    );
  });

  it("does not confirm when only the bio changes", async () => {
    await runAgent(["update", "--bio", "gm", "--json"]);
    expect(confirmAgentAction).not.toHaveBeenCalled();
    expect(updateAgentProfile).toHaveBeenCalled();
  });

  it("does not confirm when the username is unchanged", async () => {
    await runAgent(["update", "--username", AGENT_INFO.username, "--json"]);
    expect(confirmAgentAction).not.toHaveBeenCalled();
  });
});

describe("zora agent connect-email", () => {
  const PRIVY_ACCOUNT = {
    address: "0xAbC0000000000000000000000000000000000001",
    did: "did:privy:test123",
    accessToken: "header.payload.signature",
    isNewUser: false,
    linkedAccounts: [],
  };

  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
    vi.mocked(getPrivateKey).mockReturnValue(SAVED_PK);
    vi.mocked(createPrivyAccount).mockResolvedValue(PRIVY_ACCOUNT);
    vi.mocked(hasLinkedEmail).mockReturnValue(false);
    vi.mocked(sendEmailCode).mockResolvedValue(undefined);
    vi.mocked(inputOrFail).mockResolvedValue("123456");
    vi.mocked(linkEmailWithCode).mockResolvedValue({
      email: "a@b.com",
      linkedAccounts: [{ type: "email", address: "a@b.com" }],
    });
  });

  it("signs in, sends a code, links the email, and outputs JSON", async () => {
    const log = captureLog();
    await runAgent(["connect-email", "--email", "a@b.com", "--json"]);
    const parsed = JSON.parse(log.output());
    log.restore();

    expect(createPrivyAccount).toHaveBeenCalledWith(
      expect.objectContaining({
        privateKey: SAVED_PK,
        appId: "test-app-id",
        origin: "https://zora.com",
        chainId: 8453,
      }),
    );
    expect(sendEmailCode).toHaveBeenCalledWith(
      expect.objectContaining({
        accessToken: PRIVY_ACCOUNT.accessToken,
        email: "a@b.com",
      }),
    );
    // Only the code is prompted when --email is supplied.
    expect(inputOrFail).toHaveBeenCalledTimes(1);
    expect(linkEmailWithCode).toHaveBeenCalledWith(
      expect.objectContaining({ email: "a@b.com", code: "123456" }),
    );
    expect(parsed).toMatchObject({
      email: "a@b.com",
      did: PRIVY_ACCOUNT.did,
      address: PRIVY_ACCOUNT.address,
      alreadyLinked: false,
      walletSource: "/home/u/.config/zora/wallet.json",
    });
  });

  it("prompts for the email when --email is omitted, before sending the code", async () => {
    vi.mocked(inputOrFail)
      .mockResolvedValueOnce("a@b.com") // email prompt
      .mockResolvedValueOnce("123456"); // code prompt
    await runAgent(["connect-email", "--json"]);
    expect(inputOrFail).toHaveBeenCalledTimes(2);
    // sendEmailCode received the prompted address, so the prompt ran first.
    expect(sendEmailCode).toHaveBeenCalledWith(
      expect.objectContaining({ email: "a@b.com" }),
    );
    expect(linkEmailWithCode).toHaveBeenCalledWith(
      expect.objectContaining({ email: "a@b.com", code: "123456" }),
    );
  });

  it("short-circuits when the email is already linked", async () => {
    vi.mocked(hasLinkedEmail).mockReturnValue(true);
    const log = captureLog();
    await runAgent(["connect-email", "--email", "a@b.com", "--json"]);
    const parsed = JSON.parse(log.output());
    log.restore();
    expect(sendEmailCode).not.toHaveBeenCalled();
    expect(linkEmailWithCode).not.toHaveBeenCalled();
    expect(parsed).toMatchObject({
      email: "a@b.com",
      alreadyLinked: true,
      walletSource: "/home/u/.config/zora/wallet.json",
    });
  });

  it("fails before sending a code when --yes is set without --email", async () => {
    // inputOrFail is the real non-interactive guard; simulate its exit here.
    vi.mocked(inputOrFail).mockImplementation(() => {
      throw new Error("process.exit(1)");
    });
    await expect(runAgent(["connect-email", "--yes"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(createPrivyAccount).toHaveBeenCalled();
    expect(sendEmailCode).not.toHaveBeenCalled();
  });

  it("fails before sending a code when --yes is set with --email (not yet linked)", async () => {
    await expect(
      runAgent(["connect-email", "--email", "a@b.com", "--yes"]),
    ).rejects.toThrow("process.exit(1)");
    expect(createPrivyAccount).toHaveBeenCalled();
    // No OTP is sent and no code prompt is shown — we bail before step 4.
    expect(sendEmailCode).not.toHaveBeenCalled();
    expect(inputOrFail).not.toHaveBeenCalled();
  });

  it("still short-circuits with --yes when the email is already linked", async () => {
    vi.mocked(hasLinkedEmail).mockReturnValue(true);
    const log = captureLog();
    await runAgent(["connect-email", "--email", "a@b.com", "--yes", "--json"]);
    const parsed = JSON.parse(log.output());
    log.restore();
    expect(sendEmailCode).not.toHaveBeenCalled();
    expect(parsed).toMatchObject({ alreadyLinked: true });
  });

  it("rejects an invalid --email before signing in", async () => {
    await expect(
      runAgent(["connect-email", "--email", "not-an-email"]),
    ).rejects.toThrow("process.exit(1)");
    expect(createPrivyAccount).not.toHaveBeenCalled();
  });

  it("rejects an invalid --chain-id", async () => {
    await expect(
      runAgent(["connect-email", "--email", "a@b.com", "--chain-id", "abc"]),
    ).rejects.toThrow("process.exit(1)");
    expect(createPrivyAccount).not.toHaveBeenCalled();
  });

  it("exits when Privy sign-in fails", async () => {
    vi.mocked(createPrivyAccount).mockRejectedValue(new Error("network"));
    await expect(
      runAgent(["connect-email", "--email", "a@b.com"]),
    ).rejects.toThrow("process.exit(1)");
    expect(sendEmailCode).not.toHaveBeenCalled();
  });

  it("exits when sending the code fails", async () => {
    vi.mocked(sendEmailCode).mockRejectedValue(new Error("boom"));
    await expect(
      runAgent(["connect-email", "--email", "a@b.com"]),
    ).rejects.toThrow("process.exit(1)");
    expect(linkEmailWithCode).not.toHaveBeenCalled();
  });

  it("exits when no code is entered", async () => {
    vi.mocked(inputOrFail).mockResolvedValue("   ");
    await expect(
      runAgent(["connect-email", "--email", "a@b.com"]),
    ).rejects.toThrow("process.exit(1)");
    expect(linkEmailWithCode).not.toHaveBeenCalled();
  });

  it("exits when linking fails (wrong or expired code)", async () => {
    vi.mocked(linkEmailWithCode).mockRejectedValue(new Error("bad code"));
    await expect(
      runAgent(["connect-email", "--email", "a@b.com"]),
    ).rejects.toThrow("process.exit(1)");
  });

  it("renders a human-readable summary without --json", async () => {
    const log = captureLog();
    await runAgent(["connect-email", "--email", "a@b.com"]);
    const output = log.output();
    log.restore();
    expect(output).toContain("Email linked");
    expect(output).toContain("a@b.com");
    expect(output).toContain(PRIVY_ACCOUNT.did);
    expect(output).not.toContain(PRIVY_ACCOUNT.accessToken);
  });
});
