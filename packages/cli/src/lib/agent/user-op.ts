import {
  decodeErrorResult,
  encodeAbiParameters,
  encodeFunctionData,
  getAddress,
  keccak256,
  recoverAddress,
  zeroAddress,
  type Address,
  type Hex,
  type LocalAccount,
} from "viem";
import type { ChainClient } from "./zora-client.js";

/** ERC-4337 v0.6 EntryPoint (the singleton, same address on Base). */
export const ENTRY_POINT: Address =
  "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789";

const EMPTY_BYTES = "0x" as Hex;

/** A v0.6 UserOperation with its numeric fields parsed to bigint. */
export interface UserOperation {
  sender: Address;
  nonce: bigint;
  initCode: Hex;
  callData: Hex;
  callGasLimit: bigint;
  verificationGasLimit: bigint;
  preVerificationGas: bigint;
  maxFeePerGas: bigint;
  maxPriorityFeePerGas: bigint;
  paymasterAndData: Hex;
}

/** The shape the Zora tRPC builders return — bigints encoded as decimal strings. */
export interface RawUserOperation {
  sender: string;
  nonce: string;
  initCode?: string;
  callData: string;
  callGasLimit: string;
  verificationGasLimit: string;
  preVerificationGas: string;
  maxFeePerGas: string;
  maxPriorityFeePerGas: string;
  paymasterAndData?: string;
  signature?: string;
}

export function parseUserOperation(raw: RawUserOperation): UserOperation {
  return {
    sender: getAddress(raw.sender),
    nonce: BigInt(raw.nonce),
    initCode: (raw.initCode || EMPTY_BYTES) as Hex,
    callData: raw.callData as Hex,
    callGasLimit: BigInt(raw.callGasLimit),
    verificationGasLimit: BigInt(raw.verificationGasLimit),
    preVerificationGas: BigInt(raw.preVerificationGas),
    maxFeePerGas: BigInt(raw.maxFeePerGas),
    maxPriorityFeePerGas: BigInt(raw.maxPriorityFeePerGas),
    paymasterAndData: (raw.paymasterAndData || EMPTY_BYTES) as Hex,
  };
}

/** Whether the UserOp is paymaster-sponsored (the sender pays no gas). */
export function isSponsored(op: UserOperation): boolean {
  return op.paymasterAndData !== EMPTY_BYTES;
}

/** The canonical ERC-4337 v0.6 userOpHash for the given chain. */
export function userOpHash(op: UserOperation, chainId: number): Hex {
  const packed = keccak256(
    encodeAbiParameters(
      [
        { type: "address" },
        { type: "uint256" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "bytes32" },
      ],
      [
        op.sender,
        op.nonce,
        keccak256(op.initCode),
        keccak256(op.callData),
        op.callGasLimit,
        op.verificationGasLimit,
        op.preVerificationGas,
        op.maxFeePerGas,
        op.maxPriorityFeePerGas,
        keccak256(op.paymasterAndData),
      ],
    ),
  );
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "address" }, { type: "uint256" }],
      [packed, ENTRY_POINT, BigInt(chainId)],
    ),
  );
}

/**
 * Sign a UserOp with an EOA owner of the smart wallet, returning the RAW 65-byte
 * signature (over the raw userOpHash — not an EIP-191 personal_sign).
 *
 * The Zora backend wraps this into the Coinbase `SignatureWrapper` itself, so the
 * raw signature is what `submitUserOperation` expects — do not pre-wrap it there.
 */
export async function signUserOp(
  account: LocalAccount,
  op: UserOperation,
  chainId: number,
): Promise<{ hash: Hex; signature: Hex }> {
  const hash = userOpHash(op, chainId);
  if (!account.sign) {
    throw new Error("Signing account cannot sign raw hashes.");
  }
  const signature = await account.sign({ hash });
  const recovered = await recoverAddress({ hash, signature });
  if (recovered.toLowerCase() !== account.address.toLowerCase()) {
    throw new Error("UserOp signature does not recover to the signing EOA");
  }
  return { hash, signature };
}

/** Wrap a raw EOA signature into the Coinbase smart-wallet `SignatureWrapper`. */
export function wrapSignature(ownerIndex: number, signature: Hex): Hex {
  return encodeAbiParameters(
    [
      {
        type: "tuple",
        components: [
          { name: "ownerIndex", type: "uint256" },
          { name: "signatureData", type: "bytes" },
        ],
      },
    ],
    [{ ownerIndex: BigInt(ownerIndex), signatureData: signature }],
  );
}

const ENTRY_POINT_ABI = [
  {
    type: "function",
    name: "simulateHandleOp",
    stateMutability: "nonpayable",
    inputs: [
      {
        name: "op",
        type: "tuple",
        components: [
          { name: "sender", type: "address" },
          { name: "nonce", type: "uint256" },
          { name: "initCode", type: "bytes" },
          { name: "callData", type: "bytes" },
          { name: "callGasLimit", type: "uint256" },
          { name: "verificationGasLimit", type: "uint256" },
          { name: "preVerificationGas", type: "uint256" },
          { name: "maxFeePerGas", type: "uint256" },
          { name: "maxPriorityFeePerGas", type: "uint256" },
          { name: "paymasterAndData", type: "bytes" },
          { name: "signature", type: "bytes" },
        ],
      },
      { name: "target", type: "address" },
      { name: "targetCallData", type: "bytes" },
    ],
    outputs: [],
  },
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
  {
    type: "error",
    name: "FailedOp",
    inputs: [
      { name: "opIndex", type: "uint256" },
      { name: "reason", type: "string" },
    ],
  },
] as const;

// viem nests the revert data somewhere down the error's cause chain.
function extractRevertData(err: unknown): Hex | undefined {
  let cur: unknown = err;
  for (let depth = 0; depth < 8 && cur; depth++) {
    const e = cur as { data?: unknown; cause?: unknown };
    if (typeof e.data === "string" && e.data.startsWith("0x"))
      return e.data as Hex;
    const nested = (e.data as { data?: unknown } | undefined)?.data;
    if (typeof nested === "string" && nested.startsWith("0x"))
      return nested as Hex;
    cur = e.cause;
  }
  return undefined;
}

function shortMessage(err: unknown): string {
  const e = err as { shortMessage?: string; message?: string };
  return e.shortMessage || e.message || String(err);
}

/**
 * Dry-run a signed UserOp against the EntryPoint. `simulateHandleOp` always
 * reverts: `ExecutionResult` means validation (the signature) passed and the op
 * would execute; `FailedOp` (e.g. `"AA24 signature error"`) means it would be
 * rejected. Use this to confirm the signature before submitting.
 *
 * NOTE: `valid: true` confirms only that the signature was accepted and the gas
 * limits look reasonable — NOT that the inner `callData` will succeed. The
 * EntryPoint executes `op.callData` internally and swallows any revert, still
 * returning `ExecutionResult`, so a failing factory call passes this check and
 * surfaces only on submission (where the response's `success` flag is checked).
 */
export async function simulateUserOp(
  client: ChainClient,
  op: UserOperation,
  ownerIndex: number,
  signature: Hex,
): Promise<{ valid: boolean; detail: string }> {
  const data = encodeFunctionData({
    abi: ENTRY_POINT_ABI,
    functionName: "simulateHandleOp",
    args: [
      { ...op, signature: wrapSignature(ownerIndex, signature) },
      zeroAddress,
      EMPTY_BYTES,
    ],
  });
  try {
    await client.call({ to: ENTRY_POINT, data });
    return { valid: false, detail: "no revert (unexpected)" };
  } catch (err) {
    const revert = extractRevertData(err);
    if (!revert) return { valid: false, detail: shortMessage(err) };
    try {
      const decoded = decodeErrorResult({ abi: ENTRY_POINT_ABI, data: revert });
      if (decoded.errorName === "ExecutionResult") {
        return { valid: true, detail: "ExecutionResult" };
      }
      return {
        valid: false,
        detail: `${decoded.errorName}: ${String(decoded.args?.[1] ?? "")}`,
      };
    } catch {
      return { valid: false, detail: "undecodable revert" };
    }
  }
}
