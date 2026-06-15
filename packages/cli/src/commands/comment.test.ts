import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type Address, PrivateKeyAccount } from "viem";
import { createProgram } from "../test/create-program.js";

vi.mock("@inquirer/confirm");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
}));
vi.mock("../lib/wallet.js");
vi.mock("@zoralabs/coins-sdk");
vi.mock("../lib/analytics.js");

import confirm from "@inquirer/confirm";
import {
  getCoin,
  getCoinComments,
  getProfile,
  prepareUserOperation,
  submitUserOperation,
} from "@zoralabs/coins-sdk";
import { getApiKey } from "../lib/config.js";
import { createClients, resolveAccounts } from "../lib/wallet.js";
import { COMMENTS_ADDRESS } from "../lib/comments.js";
import { commentCommand } from "./comment.js";

const COIN_ADDRESS = "0x2bf7bd9c5609ffd0520d6f282713af2fc8dab914" as Address;
const EOA_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const SMART_WALLET_ADDRESS =
  "0xAbCdEf0123456789AbCdEf0123456789AbCdEf01" as Address;
const TX_HASH =
  "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const SPARK_VALUE = 1_000_000_000_000n; // 1e12 wei

function run(args: string[]) {
  const program = createProgram(commentCommand);
  return program.parseAsync(["comment", ...args], { from: "user" });
}

describe("comment command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;

  const publicClient = {
    readContract: vi.fn(),
    waitForTransactionReceipt: vi.fn(),
  };
  const walletClient = { writeContract: vi.fn() };
  const bundlerClient = {};

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: { name: "Zora", address: COIN_ADDRESS } },
    } as any);
    vi.mocked(resolveAccounts).mockResolvedValue({
      privateKeyAccount: { address: EOA_ADDRESS } as PrivateKeyAccount,
      smartWalletAccount: undefined,
    } as Awaited<ReturnType<typeof resolveAccounts>>);
    vi.mocked(createClients).mockReturnValue({
      publicClient,
      walletClient,
    } as unknown as ReturnType<typeof createClients>);
    vi.mocked(confirm).mockResolvedValue(true);

    // Default reads: spark price set, not the owner, but a holder (balance > 0)
    // so the post path runs. Individual tests override as needed.
    publicClient.readContract.mockImplementation((args: any) => {
      if (args.functionName === "sparkValue")
        return Promise.resolve(SPARK_VALUE);
      if (args.functionName === "isOwner") return Promise.resolve(false);
      if (args.functionName === "balanceOf") return Promise.resolve(1n);
      return Promise.resolve(false);
    });
    publicClient.waitForTransactionReceipt.mockResolvedValue({});
    walletClient.writeContract.mockResolvedValue(TX_HASH);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function parsedOutput(): any {
    return JSON.parse(logSpy.mock.calls.map((c) => c[0]).join("\n"));
  }

  // --- list (read) ---

  describe("list", () => {
    beforeEach(() => {
      vi.mocked(getCoinComments).mockResolvedValue({
        data: {
          zora20Token: {
            zoraComments: {
              count: 1,
              pageInfo: { hasNextPage: false },
              edges: [
                {
                  node: {
                    commentId: "0xcomment",
                    userAddress: "0x473de669566008551ce71322e52ebd70c2e44123",
                    comment: "Zora car!",
                    timestamp: 1700000000,
                    userProfile: { handle: "alexciminillo" },
                    replies: { count: 0 },
                  },
                },
              ],
            },
          },
        },
      } as any);
    });

    it("outputs comments as JSON", async () => {
      await run(["list", COIN_ADDRESS, "--json"]);
      const out = parsedOutput();
      expect(out.totalComments).toBe(1);
      expect(out.comments[0]).toMatchObject({
        author: "alexciminillo",
        authorAddress: "0x473de669566008551ce71322e52ebd70c2e44123",
        text: "Zora car!",
        replyCount: 0,
      });
      expect(getCoinComments).toHaveBeenCalledWith(
        expect.objectContaining({ address: COIN_ADDRESS, count: 20 }),
      );
    });

    it("renders a static list", async () => {
      await run(["list", COIN_ADDRESS]);
      const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(output).toContain("@alexciminillo");
      expect(output).toContain("Zora car!");
    });

    it("handles a coin with no comments", async () => {
      vi.mocked(getCoinComments).mockResolvedValue({
        data: {
          zora20Token: {
            zoraComments: {
              count: 0,
              pageInfo: { hasNextPage: false },
              edges: [],
            },
          },
        },
      } as any);
      await run(["list", COIN_ADDRESS]);
      const output = logSpy.mock.calls.map((c) => c[0]).join("\n");
      expect(output).toContain("No comments yet");
    });

    it("rejects an invalid --limit", async () => {
      await expect(
        run(["list", COIN_ADDRESS, "--limit", "999"]),
      ).rejects.toThrow("process.exit(1)");
    });

    it("shows a usage error (not a crash) when no coin is given", async () => {
      await expect(run(["list"])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Missing coin"),
      );
    });
  });

  // --- comment (post) ---

  describe("post", () => {
    it("errors when text is missing", async () => {
      await expect(run([COIN_ADDRESS])).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Missing comment text"),
      );
    });

    it("posts the trailing arg as the comment for an address reference", async () => {
      await run([COIN_ADDRESS, "hello world", "--yes"]);
      const call = walletClient.writeContract.mock.calls[0][0];
      expect(call.args[1]).toBe(COIN_ADDRESS);
      expect(call.args[3]).toBe("hello world");
    });

    it("posts the trailing arg as the comment for a typed (creator-coin) reference", async () => {
      // Regression: a type prefix makes the coin reference span two args, so the
      // comment text is the third arg — it must not be the coin name.
      vi.mocked(getProfile).mockResolvedValue({
        data: { profile: { creatorCoin: { address: COIN_ADDRESS } } },
      } as any);
      await run(["creator-coin", "somecreator", "hello world", "--yes"]);
      const call = walletClient.writeContract.mock.calls[0][0];
      expect(call.args[1]).toBe(COIN_ADDRESS);
      expect(call.args[3]).toBe("hello world");
    });

    it("requires comment text when using a typed reference", async () => {
      await expect(
        run(["creator-coin", "somecreator", "--yes"]),
      ).rejects.toThrow("process.exit(1)");
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Missing comment text"),
      );
    });

    it("errors on an invalid --referrer", async () => {
      await expect(
        run([COIN_ADDRESS, "hi", "--referrer", "nope"]),
      ).rejects.toThrow("process.exit(1)");
    });

    it("posts via EOA including one spark when not the owner", async () => {
      await run([COIN_ADDRESS, "gm", "--yes"]);

      expect(walletClient.writeContract).toHaveBeenCalledTimes(1);
      const call = walletClient.writeContract.mock.calls[0][0];
      expect(call).toMatchObject({
        address: COMMENTS_ADDRESS,
        functionName: "comment",
        value: SPARK_VALUE,
      });
      // commenter (arg 0) is the EOA; text (arg 3) is the comment
      expect(call.args[0]).toBe(EOA_ADDRESS);
      expect(call.args[1]).toBe(COIN_ADDRESS);
      expect(call.args[3]).toBe("gm");
      expect(publicClient.waitForTransactionReceipt).toHaveBeenCalled();
    });

    it("posts for free when the commenter owns the coin", async () => {
      publicClient.readContract.mockImplementation((args: any) =>
        args.functionName === "sparkValue"
          ? Promise.resolve(SPARK_VALUE)
          : Promise.resolve(true),
      );
      await run([COIN_ADDRESS, "gm", "--yes"]);
      const call = walletClient.writeContract.mock.calls[0][0];
      expect(call.value).toBe(0n);
    });

    it("posts via smart wallet when configured", async () => {
      vi.mocked(resolveAccounts).mockResolvedValue({
        privateKeyAccount: { address: EOA_ADDRESS } as PrivateKeyAccount,
        smartWalletAccount: { address: SMART_WALLET_ADDRESS } as any,
      } as Awaited<ReturnType<typeof resolveAccounts>>);
      vi.mocked(createClients).mockReturnValue({
        publicClient,
        walletClient,
        bundlerClient,
      } as unknown as ReturnType<typeof createClients>);
      vi.mocked(prepareUserOperation).mockResolvedValue({} as any);
      vi.mocked(submitUserOperation).mockResolvedValue({
        success: true,
        receipt: { transactionHash: TX_HASH },
      } as any);

      await run([COIN_ADDRESS, "gm", "--yes", "--json"]);

      expect(submitUserOperation).toHaveBeenCalled();
      expect(walletClient.writeContract).not.toHaveBeenCalled();
      const out = parsedOutput();
      expect(out.commenter).toBe(SMART_WALLET_ADDRESS);
      expect(out.tx).toBe(TX_HASH);
    });

    it("fails fast (no transaction) when the commenter holds none of the coin", async () => {
      publicClient.readContract.mockImplementation((args: any) => {
        if (args.functionName === "sparkValue")
          return Promise.resolve(SPARK_VALUE);
        if (args.functionName === "isOwner") return Promise.resolve(false);
        if (args.functionName === "balanceOf") return Promise.resolve(0n);
        return Promise.resolve(false);
      });
      await expect(run([COIN_ADDRESS, "gm", "--yes"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("must hold Zora to comment"),
      );
      expect(walletClient.writeContract).not.toHaveBeenCalled();
    });

    it("gives a holder-requirement message when the contract rejects a non-holder", async () => {
      walletClient.writeContract.mockRejectedValue(
        new Error(
          "Execution reverted: custom error 0xd8a26f99: NotTokenHolderOrAdmin()",
        ),
      );
      await expect(run([COIN_ADDRESS, "gm", "--yes"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("must hold Zora to comment"),
      );
    });

    it("aborts when the user declines confirmation", async () => {
      vi.mocked(confirm).mockResolvedValue(false);
      await expect(run([COIN_ADDRESS, "gm"])).rejects.toThrow(
        "process.exit(0)",
      );
      expect(walletClient.writeContract).not.toHaveBeenCalled();
    });
  });
});
