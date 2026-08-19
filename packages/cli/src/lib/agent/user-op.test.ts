import { describe, it, expect } from "vitest";
import { privateKeyToAccount } from "viem/accounts";
import {
  decodeAbiParameters,
  encodeErrorResult,
  recoverAddress,
  type Hex,
} from "viem";
import type { ChainClient } from "./zora-client.js";
import {
  ENTRY_POINT,
  isSponsored,
  parseUserOperation,
  signUserOp,
  simulateUserOp,
  userOpHash,
  wrapSignature,
  type UserOperation,
} from "./user-op.js";

// Anvil test account #0.
const TEST_PK =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;

const OP: UserOperation = {
  sender: "0x1111111111111111111111111111111111111111",
  nonce: 1n,
  initCode: "0x",
  callData: "0xdeadbeef",
  callGasLimit: 100000n,
  verificationGasLimit: 200000n,
  preVerificationGas: 50000n,
  maxFeePerGas: 1000000000n,
  maxPriorityFeePerGas: 1000000000n,
  paymasterAndData: "0x",
};

const EXECUTION_RESULT_ABI = [
  {
    type: "error",
    name: "ExecutionResult",
    inputs: [
      { name: "preOpGas", type: "uint256" },
      { name: "paid", type: "uint256" },
      { name: "validAfter", type: "uint48" },
      { name: "validUntil", type: "uint48" },
      { name: "targetSuccess", type: "bool" },
      { name: "targetResult", type: "bytes" },
    ],
  },
] as const;

const FAILED_OP_ABI = [
  {
    type: "error",
    name: "FailedOp",
    inputs: [
      { name: "opIndex", type: "uint256" },
      { name: "reason", type: "string" },
    ],
  },
] as const;

function clientReverting(data?: Hex): ChainClient {
  return {
    readContract: async () => "0x",
    getCode: async () => "0x",
    call: async () => {
      const err = new Error("execution reverted") as Error & { data?: Hex };
      if (data) err.data = data;
      throw err;
    },
  };
}

describe("parseUserOperation", () => {
  it("parses decimal-string fields to bigint and defaults empty bytes", () => {
    const op = parseUserOperation({
      sender: "0x1111111111111111111111111111111111111111",
      nonce: "5",
      callData: "0xabcd",
      callGasLimit: "1",
      verificationGasLimit: "2",
      preVerificationGas: "3",
      maxFeePerGas: "4",
      maxPriorityFeePerGas: "5",
    });
    expect(op.nonce).toBe(5n);
    expect(op.callGasLimit).toBe(1n);
    expect(op.initCode).toBe("0x");
    expect(op.paymasterAndData).toBe("0x");
  });
});

describe("userOpHash", () => {
  it("is a 32-byte hash, deterministic, and chain-specific", () => {
    const h = userOpHash(OP, 8453);
    expect(h).toMatch(/^0x[0-9a-f]{64}$/);
    expect(userOpHash(OP, 8453)).toBe(h);
    expect(userOpHash(OP, 1)).not.toBe(h);
  });
});

describe("isSponsored", () => {
  it("is true only when paymasterAndData is set", () => {
    expect(isSponsored(OP)).toBe(false);
    expect(isSponsored({ ...OP, paymasterAndData: "0x1234" })).toBe(true);
  });
});

describe("wrapSignature", () => {
  it("encodes the owner index + signature so they decode back", () => {
    const wrapped = wrapSignature(1, "0xbeef");
    const [decoded] = decodeAbiParameters(
      [
        {
          type: "tuple",
          components: [
            { name: "ownerIndex", type: "uint256" },
            { name: "signatureData", type: "bytes" },
          ],
        },
      ],
      wrapped,
    );
    expect((decoded as { ownerIndex: bigint }).ownerIndex).toBe(1n);
    expect((decoded as { signatureData: Hex }).signatureData).toBe("0xbeef");
    expect(wrapSignature(2, "0xbeef")).not.toBe(wrapped);
  });
});

describe("signUserOp", () => {
  it("signs the raw userOpHash so it recovers to the signer", async () => {
    const account = privateKeyToAccount(TEST_PK);
    const { hash, signature } = await signUserOp(account, OP, 8453);
    expect(hash).toBe(userOpHash(OP, 8453));
    expect((await recoverAddress({ hash, signature })).toLowerCase()).toBe(
      account.address.toLowerCase(),
    );
  });
});

describe("simulateUserOp", () => {
  it("treats ExecutionResult as a valid signature", async () => {
    const data = encodeErrorResult({
      abi: EXECUTION_RESULT_ABI,
      errorName: "ExecutionResult",
      args: [0n, 0n, 0, 0, true, "0x"],
    });
    const result = await simulateUserOp(clientReverting(data), OP, 1, "0xsig");
    expect(result.valid).toBe(true);
    expect(result.detail).toBe("ExecutionResult");
  });

  it("treats FailedOp as an invalid signature and surfaces the reason", async () => {
    const data = encodeErrorResult({
      abi: FAILED_OP_ABI,
      errorName: "FailedOp",
      args: [0n, "AA24 signature error"],
    });
    const result = await simulateUserOp(clientReverting(data), OP, 1, "0xsig");
    expect(result.valid).toBe(false);
    expect(result.detail).toContain("AA24 signature error");
  });

  it("is invalid when there is no revert data", async () => {
    const result = await simulateUserOp(clientReverting(), OP, 1, "0xsig");
    expect(result.valid).toBe(false);
  });
});

describe("ENTRY_POINT", () => {
  it("is the ERC-4337 v0.6 singleton", () => {
    expect(ENTRY_POINT).toBe("0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789");
  });
});
