import { describe, expect, it } from "vitest";
import { CoinbaseGasError } from "./userOperation";

// The constructor only reads `details`, `cause`, and `message`, but the param
// is typed with the full viem bundler-error shape, so fill the rest with stubs.
const makeBundlerError = (
  overrides: Partial<{ details: string; cause: unknown; message: string }> = {},
) => ({
  stack: "stack",
  message: overrides.message ?? "bundler error message",
  cause: "cause" in overrides ? overrides.cause : { code: -32000 },
  details: overrides.details ?? "",
  docsPath: "",
  shortMessage: "",
  version: "viem@2.x",
  name: "UserOperationExecutionError",
});

const precheck = (balance: string, required: string) =>
  `precheck failed: sender balance and deposit together is ${balance} but must be at least ${required} to pay for this operation`;

describe("CoinbaseGasError", () => {
  it("formats both balance and required when present", () => {
    // 1001597376034823 wei = 0.001001597376034823 ETH
    // 10704882000000000 wei = 0.010704882 ETH
    const error = new CoinbaseGasError(
      makeBundlerError({
        details: precheck("1001597376034823", "10704882000000000"),
      }),
    );

    expect(error.message).toBe(
      "Insufficient balance. You need at least 0.010704882 ETH to pay for this operation, but you only have 0.001001597376034823 ETH.",
    );
  });

  it("falls back to required-only when balance is missing", () => {
    const error = new CoinbaseGasError(
      makeBundlerError({ details: precheck("", "10704882000000000") }),
    );

    expect(error.message).toBe(
      "Insufficient balance. Make sure you have at least 0.010704882 ETH in your wallet.",
    );
  });

  it("falls back to generic message when only balance is present", () => {
    const error = new CoinbaseGasError(
      makeBundlerError({ details: precheck("1001597376034823", "") }),
    );

    expect(error.message).toBe(
      "Insufficient balance. Make sure you have enough ETH to pay for this operation.",
    );
  });

  it("falls back to generic message when both amounts are missing", () => {
    const error = new CoinbaseGasError(
      makeBundlerError({ details: precheck("", "") }),
    );

    expect(error.message).toBe(
      "Insufficient balance. Make sure you have enough ETH to pay for this operation.",
    );
  });

  it("uses the raw details when the precheck pattern does not match", () => {
    const details = "AA13 initCode failed or OOG";
    const error = new CoinbaseGasError(makeBundlerError({ details }));

    expect(error.message).toBe(details);
  });

  it("propagates cause and details onto the instance", () => {
    const cause = { code: -32000 };
    const details = precheck("1001597376034823", "10704882000000000");
    const error = new CoinbaseGasError(makeBundlerError({ details, cause }));

    expect(error).toBeInstanceOf(Error);
    expect(error).toBeInstanceOf(CoinbaseGasError);
    expect(error.cause).toBe(cause);
    expect(error.details).toBe(details);
  });
});
