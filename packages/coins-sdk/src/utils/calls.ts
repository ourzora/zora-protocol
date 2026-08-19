import {
  type Abi,
  type Address,
  concatHex,
  type ContractFunctionArgs,
  type ContractFunctionName,
  type ContractFunctionParameters,
  encodeFunctionData,
  type Hex,
} from "viem";

const EMPTY_HEX: Hex = "0x";

type WritableMutability = "payable" | "nonpayable";

type WritableFunction<abi extends Abi | readonly unknown[]> =
  ContractFunctionName<abi, WritableMutability>;

type WritableArgs<
  abi extends Abi | readonly unknown[],
  functionName extends WritableFunction<abi>,
> = ContractFunctionArgs<abi, WritableMutability, functionName>;

export type ContractCall<
  abi extends Abi | readonly unknown[] = readonly unknown[],
  fn extends WritableFunction<abi> = WritableFunction<abi>,
  args extends WritableArgs<abi, fn> = WritableArgs<abi, fn>,
> = ContractFunctionParameters<abi, WritableMutability, fn, args> & {
  /** Optional ETH value to send with the call. */
  value?: bigint;
  /**
   * Optional calldata appended after the encoded function data, e.g. for
   * attribution. Mirrors viem's `dataSuffix`; concatenated by {@link toGenericCall}.
   */
  dataSuffix?: Hex;
};

export const isContractCall = (
  call: ContractCall | SendCall,
): call is ContractCall => {
  return (
    (call as ContractCall).address !== undefined &&
    (call as ContractCall).abi !== undefined &&
    (call as ContractCall).functionName !== undefined
  );
};

export type SendCall = {
  to: Address;
  value?: bigint;
};

export const isSendCall = (call: ContractCall | SendCall): call is SendCall => {
  return !isContractCall(call) && (call as SendCall).to !== undefined;
};

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
 * Converts a contract call or send call to a generic call.
 */
export function toGenericCall(call: ContractCall | SendCall): GenericCall {
  // convert a simple send call to a user operation call
  if (isSendCall(call)) {
    return {
      to: call.to,
      value: call.value ?? 0n,
      data: EMPTY_HEX,
    };
  }

  // convert a contract call to a user operation call
  // if the call has a data suffix, we need to manually concatenate it with the call data
  // it is used to add the attribution to the call data
  const { dataSuffix } = call;
  const callData = encodeFunctionData(call);
  const data = dataSuffix ? concatHex([callData, dataSuffix]) : callData;

  return {
    to: call.address,
    value: call.value ?? 0n,
    data,
  };
}

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
