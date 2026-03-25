import { describe, it, expect } from "vitest";
import {
  BaseError as ViemBaseError,
  InsufficientFundsError,
  NonceTooLowError,
} from "viem";
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
