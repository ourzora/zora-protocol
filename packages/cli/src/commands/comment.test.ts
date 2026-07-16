import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Address } from "viem";
import { createProgram } from "../test/create-program.js";

vi.mock("@inquirer/confirm");
// resolveCoinTarget resolves a coin ref via the indexer; stub it so the tests
// drive the comment path directly without any network.
vi.mock("../lib/comment-target.js", () => ({ resolveCoinTarget: vi.fn() }));
vi.mock("../lib/comments.js", () => ({
  createOffChainComment: vi.fn(),
  listCoinComments: vi.fn(),
  MAX_COMMENT_LENGTH: 280,
  COIN_OFF_CHAIN_TOKEN_ID: "0",
}));
vi.mock("../lib/coin-ref.js", () => ({
  isCoinTypeKeyword: (s: string) => s === "creator-coin" || s === "trend",
}));
vi.mock("../lib/mentions.js", () => ({
  resolveMentions: vi.fn(),
  toPlainMentions: (t: string) => t,
}));
vi.mock("../lib/config.js", () => ({ getPrivateKey: vi.fn() }));
vi.mock("../lib/privy-session.js", () => ({ ensurePrivySession: vi.fn() }));
vi.mock("../lib/wallet.js", () => ({ normalizeKey: (k: string) => k }));
vi.mock("../lib/analytics.js", () => ({
  track: vi.fn(),
  shutdownAnalytics: vi.fn(),
}));

import confirm from "@inquirer/confirm";
import { resolveCoinTarget } from "../lib/comment-target.js";
import { resolveMentions } from "../lib/mentions.js";
import { createOffChainComment, listCoinComments } from "../lib/comments.js";
import { getPrivateKey } from "../lib/config.js";
import { ensurePrivySession } from "../lib/privy-session.js";
import { track } from "../lib/analytics.js";
import { commentCommand } from "./comment.js";

const PK = `0x${"a".repeat(64)}`;
const COIN = "0x2bf7bd9c5609ffd0520d6f282713af2fc8dab914" as Address;
const TOKEN = "privy.jwt.token";

function run(args: string[]) {
  const program = createProgram(commentCommand);
  return program.parseAsync(["comment", ...args], { from: "user" });
}

describe("comment command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let savedEnvKey: string | undefined;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    // The command reads ZORA_PRIVATE_KEY before getPrivateKey(); clear it so the
    // mocked getPrivateKey is the single source of truth in tests.
    savedEnvKey = process.env.ZORA_PRIVATE_KEY;
    delete process.env.ZORA_PRIVATE_KEY;

    vi.mocked(getPrivateKey).mockReturnValue(PK);
    vi.mocked(ensurePrivySession).mockResolvedValue({
      accessToken: TOKEN,
    } as Awaited<ReturnType<typeof ensurePrivySession>>);
    vi.mocked(resolveCoinTarget).mockResolvedValue({
      address: COIN,
      name: "Zora",
    });
    // Default: no mentions — the text passes through unchanged.
    vi.mocked(resolveMentions).mockImplementation(async (t: string) => ({
      text: t,
      resolved: [],
      skipped: [],
    }));
    vi.mocked(confirm).mockResolvedValue(true);
    vi.mocked(createOffChainComment).mockResolvedValue({
      commentId: "cmt_1",
      text: "gm",
      commentedAt: "2026-01-01T00:00:00Z",
      cursor: "c1",
      handle: "agent",
      profileId: "agent",
    });
  });

  afterEach(() => {
    if (savedEnvKey !== undefined) process.env.ZORA_PRIVATE_KEY = savedEnvKey;
    vi.restoreAllMocks();
    vi.clearAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  it("posts an off-chain comment and outputs JSON", async () => {
    await run([COIN, "gm", "--json"]);

    expect(createOffChainComment).toHaveBeenCalledWith(TOKEN, {
      chainName: "BaseMainnet",
      contractAddress: COIN,
      tokenId: "0",
      text: "gm",
    });
    expect(parsedOutput()).toEqual({
      action: "comment",
      offChain: true,
      coin: { name: "Zora", address: COIN },
      commentId: "cmt_1",
      text: "gm",
      commentedAt: "2026-01-01T00:00:00Z",
      handle: "agent",
    });
  });

  it("tracks a cli_comment post success event", async () => {
    await run([COIN, "gm", "--json"]);
    expect(track).toHaveBeenCalledWith(
      "cli_comment",
      expect.objectContaining({
        action: "post",
        coin_address: COIN,
        success: true,
        off_chain: true,
        comment_id: "cmt_1",
      }),
    );
  });

  it("posts the mention-encoded text and reports the mention count", async () => {
    const encoded = "gm [@alice](https://zora.co/@0xabc) welcome";
    vi.mocked(resolveMentions).mockResolvedValue({
      text: encoded,
      resolved: [{ handle: "alice", address: "0xabc" }],
      skipped: [],
    });

    await run([COIN, "gm @alice welcome", "--json"]);

    expect(resolveMentions).toHaveBeenCalledWith("gm @alice welcome");
    expect(createOffChainComment).toHaveBeenCalledWith(
      TOKEN,
      expect.objectContaining({ text: encoded }),
    );
    expect(track).toHaveBeenCalledWith(
      "cli_comment",
      expect.objectContaining({ success: true, mention_count: 1 }),
    );
  });

  it("rejects when the mention-encoded text exceeds the length limit", async () => {
    // A short typed comment can blow past 280 once a mention expands to a token.
    vi.mocked(resolveMentions).mockResolvedValue({
      text: "x".repeat(281),
      resolved: [{ handle: "alice", address: "0xabc" }],
      skipped: [],
    });
    await expect(run([COIN, "gm @alice", "--json"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(createOffChainComment).not.toHaveBeenCalled();
  });

  it("does not require holding the coin (no on-chain gate)", async () => {
    // No balance check runs — a successful post is proof the off-chain path
    // never gates on holdings (unlike the retired on-chain comment path).
    await run([COIN, "gm", "--yes"]);
    expect(createOffChainComment).toHaveBeenCalledOnce();
  });

  it("shifts the text to the third arg with a type prefix", async () => {
    await run(["creator-coin", "myname", "gm", "--json"]);
    expect(resolveCoinTarget).toHaveBeenCalledWith(
      true,
      "creator-coin",
      "myname",
      "comment",
    );
    expect(createOffChainComment).toHaveBeenCalledWith(
      TOKEN,
      expect.objectContaining({ text: "gm" }),
    );
  });

  it("prompts for confirmation and aborts when declined", async () => {
    vi.mocked(confirm).mockResolvedValue(false);
    // Declining is a clean exit (code 0), surfaced as a CliExitError.
    await expect(run([COIN, "gm"])).rejects.toThrow("process.exit(0)");
    expect(confirm).toHaveBeenCalled();
    expect(createOffChainComment).not.toHaveBeenCalled();
    expect(errorSpy).toHaveBeenCalledWith("Aborted.");
  });

  it("errors when the comment text is missing", async () => {
    await expect(run([COIN, "--json"])).rejects.toThrow("process.exit(1)");
    expect(createOffChainComment).not.toHaveBeenCalled();
  });

  it("rejects a comment over the length limit", async () => {
    const tooLong = "x".repeat(281);
    await expect(run([COIN, tooLong, "--json"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(createOffChainComment).not.toHaveBeenCalled();
  });

  it("errors with setup guidance when no wallet is configured", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    await expect(run([COIN, "gm", "--json"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(createOffChainComment).not.toHaveBeenCalled();
  });

  it("tracks a cli_comment post failure event and exits when the mutation fails", async () => {
    vi.mocked(createOffChainComment).mockRejectedValue(
      new Error("Rate limit exceeded"),
    );
    await expect(run([COIN, "gm", "--json"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(track).toHaveBeenCalledWith(
      "cli_comment",
      expect.objectContaining({
        action: "post",
        coin_address: COIN,
        success: false,
        off_chain: true,
        mention_count: 0,
        error_type: "Error",
      }),
    );
  });
});

describe("comment list command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;

  function runList(args: string[]) {
    const program = createProgram(commentCommand);
    return program.parseAsync(["comment", "list", ...args], {
      from: "user",
    });
  }

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});

    vi.mocked(resolveCoinTarget).mockResolvedValue({
      address: COIN,
      name: "Zora",
    });
    vi.mocked(listCoinComments).mockResolvedValue({
      comments: [
        {
          commentId: "onchain-1",
          offChain: false,
          text: "gm",
          timestamp: 1_700_000_000,
          handle: "alice",
          authorAddress: "0xabc",
          sparkCount: 0,
          replyCount: 2,
        },
        {
          commentId: "offchain-1",
          offChain: true,
          text: "welcome",
          timestamp: 1_700_000_100,
          handle: "bob",
          sparkCount: 3,
          replyCount: 0,
        },
      ],
      totalCount: 42,
      nextCursor: "cursor-2",
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.clearAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  it("lists merged comments as JSON with a next cursor", async () => {
    await runList([COIN, "--json"]);
    expect(listCoinComments).toHaveBeenCalledWith({
      chainId: 8453,
      address: COIN,
      first: 20,
      after: undefined,
    });
    const out = parsedOutput();
    expect(out.totalComments).toBe(42);
    expect(out.nextCursor).toBe("cursor-2");
    expect(out.comments).toHaveLength(2);
    expect(out.comments[0]).toMatchObject({
      commentId: "onchain-1",
      offChain: false,
      authorAddress: "0xabc",
    });
    expect(out.comments[1]).toMatchObject({
      commentId: "offchain-1",
      offChain: true,
    });
    // Off-chain comments have no wallet address.
    expect(out.comments[1].authorAddress).toBeUndefined();
  });

  it("passes --limit and --after through to the query", async () => {
    await runList([COIN, "--limit", "50", "--after", "cursor-1", "--json"]);
    expect(listCoinComments).toHaveBeenCalledWith({
      chainId: 8453,
      address: COIN,
      first: 50,
      after: "cursor-1",
    });
  });

  it("rejects an out-of-range --limit", async () => {
    await expect(runList([COIN, "--limit", "500"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(listCoinComments).not.toHaveBeenCalled();
  });

  it("tracks a cli_comment list success event with on/off-chain counts", async () => {
    await runList([COIN, "--json"]);
    expect(track).toHaveBeenCalledWith(
      "cli_comment",
      expect.objectContaining({
        action: "list",
        coin_address: COIN,
        success: true,
        result_count: 2,
        offchain_count: 1,
        onchain_count: 1,
      }),
    );
  });

  it("renders an empty-state message when there are no comments", async () => {
    vi.mocked(listCoinComments).mockResolvedValue({
      comments: [],
      totalCount: 0,
    });
    await runList([COIN]);
    const out = logSpy.mock.calls.map((c) => c[0]).join("\n");
    expect(out).toContain("No comments yet on Zora.");
  });

  it("surfaces a fetch failure and tracks a cli_comment list failure event", async () => {
    vi.mocked(listCoinComments).mockRejectedValue(new Error("network down"));
    // Non-JSON so the error routes to console.error (JSON mode writes to stdout).
    await expect(runList([COIN])).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Failed to fetch comments"),
    );
    expect(track).toHaveBeenCalledWith(
      "cli_comment",
      expect.objectContaining({
        action: "list",
        coin_address: COIN,
        success: false,
        error_type: "Error",
      }),
    );
  });
});
