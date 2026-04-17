import { apiPost } from "@zoralabs/coins-sdk";
import { createPublicClient, createWalletClient, custom } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { getPrivateKey } from "./config.js";
import { safeExit, ERROR } from "./exit.js";
import { formatError } from "./errors.js";

export const normalizeKey = (key: string): `0x${string}` =>
  (key.startsWith("0x") ? key : `0x${key}`) as `0x${string}`;

export const resolveAccount = (
  json = false,
): ReturnType<typeof privateKeyToAccount> => {
  const envKey = process.env.ZORA_PRIVATE_KEY;
  const key = envKey || getPrivateKey();

  if (!key) {
    console.error(
      "No wallet configured. Run 'zora setup' to create or import one.",
    );
    safeExit(ERROR);
  }

  try {
    return privateKeyToAccount(normalizeKey(key));
  } catch (err) {
    console.error(`✗ Invalid private key: ${formatError(err)}`);
    console.error("  Run 'zora setup --force' to replace it.");
    safeExit(ERROR);
  }
};

function formatRpcError(error: unknown): string {
  if (typeof error === "string") return error;
  if (error instanceof Error) return error.message;
  if (error && typeof error === "object" && "message" in error) {
    const message = (error as { message?: unknown }).message;
    if (typeof message === "string") return message;
  }

  return JSON.stringify(error);
}

function extractRpcHexData(data: unknown): string | undefined {
  if (typeof data === "string" && data.startsWith("0x") && data.length >= 10) {
    return data;
  }

  if (data && typeof data === "object" && "data" in data) {
    return extractRpcHexData((data as { data?: unknown }).data);
  }

  return undefined;
}

/**
 * Build an Error that preserves JSON-RPC code/data so viem can classify it
 * (e.g. code 3 → ContractFunctionRevertedError with revert bytes).
 */
function buildRpcError(rpcError: unknown): Error {
  if (
    rpcError &&
    typeof rpcError === "object" &&
    "code" in rpcError &&
    typeof (rpcError as { code: unknown }).code === "number"
  ) {
    const typed = rpcError as {
      code: number;
      message?: string;
      data?: unknown;
    };
    const err = new Error(typed.message ?? "RPC error");
    (err as any).code = typed.code;
    if (typed.data !== undefined) {
      (err as any).data = extractRpcHexData(typed.data) ?? typed.data;
    }
    return err;
  }
  return new Error(`CLI RPC request failed: ${formatRpcError(rpcError)}`);
}

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
        throw buildRpcError(response.error);
      }

      const payload = response.data;

      if (
        payload &&
        typeof payload === "object" &&
        "error" in payload &&
        payload.error
      ) {
        throw buildRpcError(payload.error);
      }

      if (payload && typeof payload === "object" && "result" in payload) {
        return payload.result;
      }

      return payload;
    },
  });
}

export function createClients(account: ReturnType<typeof privateKeyToAccount>) {
  const transport = createCliRpcTransport();

  const publicClient = createPublicClient({
    chain: base,
    transport,
  });

  const walletClient = createWalletClient({
    chain: base,
    transport,
    account,
  });

  return { publicClient, walletClient };
}
