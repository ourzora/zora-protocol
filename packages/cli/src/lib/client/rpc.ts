import { apiPost } from "@zoralabs/coins-sdk";
import { custom } from "viem";
import { base } from "viem/chains";

// some small helpers to improve code readability

const isObject = (value: unknown): value is Record<PropertyKey, unknown> =>
  !!value && typeof value === "object";

const hasProperty = <K extends PropertyKey>(
  obj: unknown,
  prop: K,
): obj is Record<K, unknown> => isObject(obj) && prop in obj;

/**
 * Format a RPC error into a human-readable string.
 */
function formatRpcError(error: unknown): string {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  if (hasProperty(error, "message") && typeof error.message === "string") {
    return error.message;
  }

  return JSON.stringify(error);
}

/**
 * Extract a hex string from a RPC error.
 */
function extractRpcErrorHexData(data: unknown): string | undefined {
  if (typeof data === "string" && data.startsWith("0x") && data.length >= 10) {
    return data;
  }

  if (hasProperty(data, "data")) {
    return extractRpcErrorHexData(data.data);
  }

  return undefined;
}

/**
 * Create an Error that preserves JSON-RPC code/data so viem can classify it
 * (e.g. code 3 → ContractFunctionRevertedError with revert bytes).
 */
function createRpcError(rpcError: unknown): Error {
  if (hasProperty(rpcError, "code") && typeof rpcError.code === "number") {
    const typed = rpcError as {
      code: number;
      message?: string;
      data?: unknown;
    };
    const err = new Error(typed.message ?? "RPC error");
    (err as any).code = typed.code;
    if (typed.data !== undefined) {
      (err as any).data = extractRpcErrorHexData(typed.data) ?? typed.data;
    }
    return err;
  }
  return new Error(`CLI RPC request failed: ${formatRpcError(rpcError)}`);
}

/**
 * Create a custom transport for viem that routes RPC requests through /cli-rpc and unwraps result payloads.
 */
export function createCliRpcTransport(chainId: number = base.id) {
  return custom({
    async request({
      method,
      params,
    }: {
      method: string;
      params?: readonly unknown[] | undefined;
    }) {
      let response;
      try {
        response = await apiPost("/cli-rpc", {
          chainId,
          method,
          params: params ?? [],
        });
      } catch (err) {
        throw new Error(`CLI RPC request failed: ${formatRpcError(err)}`);
      }

      if (response.error) {
        throw createRpcError(response.error);
      }

      const payload = response.data;

      if (hasProperty(payload, "error") && !!payload.error) {
        throw createRpcError(payload.error);
      }

      if (hasProperty(payload, "result")) {
        return payload.result;
      }

      return payload;
    },
  });
}
