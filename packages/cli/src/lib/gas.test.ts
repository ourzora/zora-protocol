import { describe, expect, it } from "vitest";
import { formatEther, type Account } from "viem";
import { CoinbaseGasError } from "@zoralabs/coins-sdk";
import { gasErrorSuggestion } from "./gas.js";

const ADDRESS = "0x1234567890abcdef1234567890abcdef12345678" as const;

const smartAccount = { address: ADDRESS, type: "smart" } as unknown as Account;
const eoaAccount = { address: ADDRESS, type: "local" } as unknown as Account;

/** Builds a CoinbaseGasError from a bundler `details` string (the only field it parses). */
function gasError(details: string): CoinbaseGasError {
  return new CoinbaseGasError({
    details,
    message: details,
    cause: undefined,
    stack: "",
    docsPath: "",
    shortMessage: "",
    version: "",
    name: "HttpRequestError",
  });
}

const PRECHECK_WITH_AMOUNTS =
  "precheck failed: sender balance and deposit together is 1000 but must be at least 5000 to pay for this operation";

describe("gasErrorSuggestion", () => {
  it("suggests a buffered top-up amount for a smart wallet gas error", () => {
    const suggestion = gasErrorSuggestion(
      gasError(PRECHECK_WITH_AMOUNTS),
      smartAccount,
    );

    // missing = 5000 - 1000 = 4000 wei; +50% buffer = 6000 wei
    expect(suggestion).toContain("Top up your smart wallet");
    expect(suggestion).toContain(ADDRESS);
    expect(suggestion).toContain(formatEther(6000n));
  });

  it("falls back to a default top-up suggestion when amounts can't be parsed", () => {
    const suggestion = gasErrorSuggestion(
      gasError("precheck failed: sender balance and deposit together is low"),
      smartAccount,
    );

    expect(suggestion).toContain("Ensure your smart wallet has enough ETH");
    expect(suggestion).toContain(ADDRESS);
  });

  it("returns undefined for an EOA account (no smart wallet to fund)", () => {
    expect(
      gasErrorSuggestion(gasError(PRECHECK_WITH_AMOUNTS), eoaAccount),
    ).toBeUndefined();
  });

  it("returns undefined for a non-gas error even on a smart wallet", () => {
    expect(gasErrorSuggestion(new Error("boom"), smartAccount)).toBeUndefined();
  });
});
