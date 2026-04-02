import { describe, it, expect } from "vitest";
import {
  BaseError as ViemBaseError,
  ContractFunctionRevertedError,
  InsufficientFundsError,
  NonceTooLowError,
  createPublicClient,
  custom,
  encodeErrorResult,
} from "viem";
import { base } from "viem/chains";
import {
  formatError,
  tradeErrorMessage,
  apiErrorMessage,
  fsErrorMessage,
} from "./errors.js";

describe("formatError", () => {
  it("stringifies non-Error values", () => {
    expect(formatError("raw string")).toBe("raw string");
    expect(formatError(42)).toBe("42");
  });

  it("passes through short messages", () => {
    expect(formatError(new Error("Something broke"))).toBe("Something broke");
  });

  it("truncates at 120 chars", () => {
    const long = "x".repeat(200);
    const result = formatError(new Error(long));
    expect(result).toBe("x".repeat(120) + "...");
  });
});

describe("tradeErrorMessage", () => {
  it("InsufficientFundsError gives CLI-specific guidance", () => {
    const err = new InsufficientFundsError();
    expect(tradeErrorMessage(err)).toMatch(/Not enough funds/);
    expect(tradeErrorMessage(err)).toMatch(/zora balance spendable/);
  });

  it("walks cause chain to find InsufficientFundsError", () => {
    const inner = new InsufficientFundsError();
    const outer = new ViemBaseError("wrapper", { cause: inner });
    expect(tradeErrorMessage(outer)).toMatch(/Not enough funds/);
  });

  it("uses shortMessage for other viem errors", () => {
    const err = new NonceTooLowError({ nonce: 5 });
    expect(tradeErrorMessage(err)).toBe(err.shortMessage);
  });

  it("generic ViemBaseError uses shortMessage", () => {
    const err = new ViemBaseError("Something went wrong");
    expect(tradeErrorMessage(err)).toBe("Something went wrong");
  });

  it("falls through to apiErrorMessage for non-viem errors", () => {
    const err = new Error("connect ECONNREFUSED");
    (err as NodeJS.ErrnoException).code = "ECONNREFUSED";
    expect(tradeErrorMessage(err)).toMatch(/Check your internet/);
  });

  it("truncates unknown errors", () => {
    expect(tradeErrorMessage(new Error("oops"))).toBe("oops");
  });

  it("decodes SlippageBoundsExceeded revert into friendly message", () => {
    const abi = [
      { type: "error" as const, name: "SlippageBoundsExceeded", inputs: [] },
    ];
    const data = encodeErrorResult({
      abi,
      errorName: "SlippageBoundsExceeded",
    });
    const inner = new ContractFunctionRevertedError({
      abi,
      data,
      functionName: "sell",
    });
    const outer = new ViemBaseError("execution reverted", { cause: inner });
    expect(tradeErrorMessage(outer)).toMatch(/Price moved too much/);
    expect(tradeErrorMessage(outer)).toMatch(/--slippage/);
  });

  it("decodes InsufficientLiquidity revert into friendly message", () => {
    const abi = [
      { type: "error" as const, name: "InsufficientLiquidity", inputs: [] },
    ];
    const data = encodeErrorResult({ abi, errorName: "InsufficientLiquidity" });
    const inner = new ContractFunctionRevertedError({
      abi,
      data,
      functionName: "sell",
    });
    const outer = new ViemBaseError("execution reverted", { cause: inner });
    expect(tradeErrorMessage(outer)).toMatch(/Not enough liquidity/);
  });

  it("decodes OnlyWeth revert into friendly message", () => {
    const abi = [{ type: "error" as const, name: "OnlyWeth", inputs: [] }];
    const data = encodeErrorResult({ abi, errorName: "OnlyWeth" });
    const inner = new Error("revert");
    (inner as any).data = data;
    const outer = new ViemBaseError("call failed", { cause: inner });
    expect(tradeErrorMessage(outer)).toBe("This function only accepts WETH.");
  });

  it("shows raw error name for unknown contract errors", () => {
    const abi = [{ type: "error" as const, name: "SomeNewError", inputs: [] }];
    const data = encodeErrorResult({ abi, errorName: "SomeNewError" });
    const inner = new ContractFunctionRevertedError({
      abi,
      data,
      functionName: "swap",
    });
    const outer = new ViemBaseError("execution reverted", { cause: inner });
    expect(tradeErrorMessage(outer)).toBe("Transaction reverted: SomeNewError");
  });

  it("decodes revert data from cause chain when no ContractFunctionRevertedError", () => {
    const abi = [
      { type: "error" as const, name: "SlippageBoundsExceeded", inputs: [] },
    ];
    const data = encodeErrorResult({
      abi,
      errorName: "SlippageBoundsExceeded",
    });
    // Simulate an error chain where raw data is in a nested cause
    const inner = new Error("revert");
    (inner as any).data = data;
    const outer = new ViemBaseError("call failed", { cause: inner });
    expect(tradeErrorMessage(outer)).toMatch(/Price moved too much/);
  });

  it("decodes nested object revert data from a real viem call error", async () => {
    const abi = [
      { type: "error" as const, name: "SlippageBoundsExceeded", inputs: [] },
    ];
    const data = encodeErrorResult({
      abi,
      errorName: "SlippageBoundsExceeded",
    });
    const client = createPublicClient({
      chain: base,
      transport: custom({
        async request() {
          const err = new Error("execution reverted");
          (err as any).code = 3;
          (err as any).data = { data };
          throw err;
        },
      }),
    });

    try {
      await client.call({
        to: "0x0000000000000000000000000000000000000000",
        data: "0x",
      });
      expect.fail("should have thrown");
    } catch (err) {
      expect(tradeErrorMessage(err)).toMatch(/Price moved too much/);
    }
  });

  it("shows reason string from ContractFunctionRevertedError", () => {
    const inner = new ContractFunctionRevertedError({
      abi: [],
      functionName: "sell",
    });
    // Manually set the reason (simulates a require("insufficient balance") revert)
    (inner as any).reason = "insufficient balance";
    const outer = new ViemBaseError("execution reverted", { cause: inner });
    expect(tradeErrorMessage(outer)).toBe(
      "Transaction reverted: insufficient balance",
    );
  });
});

describe("apiErrorMessage", () => {
  const makeNodeError = (code: string) => {
    const err = new Error(code);
    (err as NodeJS.ErrnoException).code = code;
    return err;
  };

  const makeHttpError = (status: number) => {
    const err = new Error("request failed");
    (err as any).status = status;
    return err;
  };

  it("ECONNREFUSED", () => {
    expect(apiErrorMessage(makeNodeError("ECONNREFUSED"))).toMatch(
      /Check your internet/,
    );
  });

  it("ENOTFOUND", () => {
    expect(apiErrorMessage(makeNodeError("ENOTFOUND"))).toMatch(
      /Check your internet/,
    );
  });

  it("ETIMEDOUT", () => {
    expect(apiErrorMessage(makeNodeError("ETIMEDOUT"))).toMatch(/timed out/);
  });

  it("UND_ERR_CONNECT_TIMEOUT", () => {
    expect(apiErrorMessage(makeNodeError("UND_ERR_CONNECT_TIMEOUT"))).toMatch(
      /timed out/,
    );
  });

  it("UND_ERR_CONNECT_TIMEOUT", () => {
    expect(apiErrorMessage(makeNodeError("UND_ERR_CONNECT_TIMEOUT"))).toMatch(
      /timed out/,
    );
  });

  it("429 rate limit", () => {
    expect(apiErrorMessage(makeHttpError(429))).toMatch(/Rate limited/);
  });

  it("401/403 auth", () => {
    expect(apiErrorMessage(makeHttpError(401))).toMatch(/Auth failed/);
    expect(apiErrorMessage(makeHttpError(403))).toMatch(/Auth failed/);
  });

  it("5xx server error", () => {
    expect(apiErrorMessage(makeHttpError(500))).toMatch(
      /temporarily unavailable/,
    );
    expect(apiErrorMessage(makeHttpError(502))).toMatch(
      /temporarily unavailable/,
    );
  });

  it("unknown errors fall through to formatError", () => {
    expect(apiErrorMessage(new Error("weird"))).toBe("weird");
  });
});

describe("fsErrorMessage", () => {
  it("EACCES includes path", () => {
    const err = new Error("EACCES");
    (err as NodeJS.ErrnoException).code = "EACCES";
    expect(fsErrorMessage(err, "~/.config/zora/config.json")).toMatch(
      /Permission denied accessing.*config\.json/,
    );
  });

  it("EISDIR includes path", () => {
    const err = new Error("EISDIR");
    (err as NodeJS.ErrnoException).code = "EISDIR";
    expect(fsErrorMessage(err, "/some/path")).toMatch(
      /directory.*\/some\/path/,
    );
  });

  it("unknown errors fall through to formatError", () => {
    expect(fsErrorMessage(new Error("disk full"), "/path")).toBe("disk full");
  });
});
