import { Address, Hex } from "viem";

/**
 * A normalized, fully-encoded contract call.
 *
 * This is the canonical call shape emitted by the action `createAndValidate*Calls`
 * builders. It intentionally matches the encoded-call form accepted by both
 * `walletClient.sendTransaction` (EOA execution) and viem's bundler client
 * `prepareUserOperation` / `sendUserOperation` (smart wallet / user operation
 * execution), so a single call list can drive either flow.
 */
export type GenericCall = {
  to: Address;
  data: Hex;
  value: bigint;
};

/**
 * The encoded-call shape accepted by viem's bundler client `calls` parameter
 * (`prepareUserOperation` / `sendUserOperation`).
 *
 * `data` and `value` are optional on viem's side; we always populate them from a
 * {@link GenericCall}.
 */
export type UserOperationCall = {
  to: Address;
  data?: Hex;
  value?: bigint;
};

/**
 * Adapts a list of {@link GenericCall} into the call shape expected by viem's
 * bundler client.
 *
 * A {@link GenericCall} is already fully encoded calldata, so this is a thin
 * adapter rather than an encoder. It exists as an explicit seam: it owns any
 * future divergence between our `GenericCall` shape and viem's user-operation
 * call type, and keeps the conversion point obvious at call sites.
 */
export function toUserOperationCalls(
  calls: GenericCall[],
): UserOperationCall[] {
  return calls.map((call) => ({
    to: call.to,
    data: call.data,
    value: call.value,
  }));
}
