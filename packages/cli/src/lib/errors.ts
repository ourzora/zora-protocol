import {
  BaseError as ViemBaseError,
  ContractFunctionRevertedError,
  InsufficientFundsError,
  decodeErrorResult,
  type Abi,
  type Hex,
} from "viem";

/**
 * Minimal error-only ABI covering Solidity custom errors users can hit during trades.
 * Kept inline to avoid depending on the contracts package.
 */
const TRADE_ERROR_ABI = [
  { type: "error", name: "SlippageBoundsExceeded", inputs: [] },
  { type: "error", name: "InsufficientLiquidity", inputs: [] },
  { type: "error", name: "InsufficientFunds", inputs: [] },
  { type: "error", name: "EthAmountTooSmall", inputs: [] },
  { type: "error", name: "EthAmountMismatch", inputs: [] },
  { type: "error", name: "ERC20TransferAmountMismatch", inputs: [] },
  { type: "error", name: "EthTransferFailed", inputs: [] },
  { type: "error", name: "EthTransferInvalid", inputs: [] },
  { type: "error", name: "MarketNotGraduated", inputs: [] },
  { type: "error", name: "MarketAlreadyGraduated", inputs: [] },
  { type: "error", name: "NotEnoughLiquidity", inputs: [] },
  { type: "error", name: "InsufficientOutputAmount", inputs: [] },
  { type: "error", name: "InvalidPrice", inputs: [] },
  { type: "error", name: "InvalidPriceOrLiquidity", inputs: [] },
  { type: "error", name: "PriceOverflow", inputs: [] },
  {
    type: "error",
    name: "SwapReverted",
    inputs: [{ name: "error", type: "bytes" }],
  },
  {
    type: "error",
    name: "OnlyPool",
    inputs: [
      { name: "sender", type: "address" },
      { name: "pool", type: "address" },
    ],
  },
  { type: "error", name: "OnlyWeth", inputs: [] },
] as const satisfies Abi;

/**
 * Maps Solidity custom error names to user-friendly messages.
 *
 * Slippage / price errors — triggered when market conditions shift between quote and execution.
 * Liquidity errors — triggered when the pool lacks depth for the requested trade size.
 * Transfer errors — triggered by ETH/ERC20 send failures or currency mismatches.
 * Market state errors — triggered when the coin's bonding curve is in the wrong phase.
 * Access errors — triggered by internal contract routing issues (should not reach users normally).
 */
const TRADE_ERROR_MESSAGES: Record<string, string> = {
  // Slippage / price
  SlippageBoundsExceeded:
    "Price moved too much during your trade. Try increasing --slippage (e.g. --slippage 3) or reducing the amount.",
  InsufficientOutputAmount:
    "Trade would produce less output than the minimum. Try increasing --slippage or reducing the amount.",
  InvalidPrice:
    "Invalid price calculation. The pool may be in an unusual state. Try again later.",
  InvalidPriceOrLiquidity:
    "Invalid price or liquidity state. The pool may be in an unusual state. Try again later.",
  PriceOverflow: "Price calculation overflow. Try a smaller trade amount.",

  // Liquidity
  InsufficientLiquidity:
    "Not enough liquidity in the pool for this trade. Try a smaller amount.",
  NotEnoughLiquidity:
    "Not enough liquidity in the pool for this trade. Try a smaller amount.",
  InsufficientFunds:
    "Not enough funds. Try a lower amount or run 'zora balance spendable' to check your balance.",

  // Transfer
  EthAmountTooSmall:
    "ETH amount is too small to execute this trade. Try a larger amount.",
  EthAmountMismatch:
    "ETH amount sent doesn't match the expected value. Please report this issue.",
  ERC20TransferAmountMismatch:
    "Token transfer amount mismatch. The token may have a transfer fee. Try a different amount.",
  EthTransferFailed: "ETH transfer failed. The recipient may not accept ETH.",
  EthTransferInvalid:
    "Invalid ETH transfer. This trade uses a token pair that doesn't involve ETH.",
  SwapReverted:
    "The underlying swap failed. Try a different amount or increasing --slippage.",

  // Market state
  MarketNotGraduated:
    "This coin's market hasn't graduated yet. It may not support this trade type.",
  MarketAlreadyGraduated:
    "This coin's market has already graduated. Try trading through the graduated pool.",

  // Access (internal routing — unlikely to reach users)
  OnlyPool: "This function can only be called by the pool contract.",
  OnlyWeth: "This function only accepts WETH.",
};

/** Walk viem's error cause chain to find raw revert hex data. */
function findHexData(value: unknown): Hex | undefined {
  if (
    typeof value === "string" &&
    value.startsWith("0x") &&
    value.length >= 10
  ) {
    return value as Hex;
  }

  if (value && typeof value === "object" && "data" in value) {
    return findHexData((value as { data?: unknown }).data);
  }

  return undefined;
}

/** Walk viem's error cause chain to find raw revert hex data. */
function extractRevertData(err: ViemBaseError): Hex | undefined {
  let current: unknown = err;
  while (current && typeof current === "object") {
    const data = findHexData((current as Record<string, unknown>).data);
    if (data) return data;
    current = (current as { cause?: unknown }).cause;
  }
  return undefined;
}

/** Try to decode a revert error name from the error, returning the friendly message or raw name. */
function decodeTradeRevert(err: ViemBaseError): string | undefined {
  // First: check if viem already parsed a ContractFunctionRevertedError
  const revertError = err.walk(
    (e) => e instanceof ContractFunctionRevertedError,
  );
  if (revertError instanceof ContractFunctionRevertedError) {
    const errorName = revertError.data?.errorName;
    if (errorName && errorName !== "Error" && errorName !== "Panic") {
      return (
        TRADE_ERROR_MESSAGES[errorName] ?? `Transaction reverted: ${errorName}`
      );
    }
    if (revertError.reason) {
      return `Transaction reverted: ${revertError.reason}`;
    }
  }

  // Second: try to extract raw revert data and decode it ourselves
  const revertData = extractRevertData(err);
  if (revertData) {
    try {
      const decoded = decodeErrorResult({
        abi: TRADE_ERROR_ABI,
        data: revertData,
      });
      return (
        TRADE_ERROR_MESSAGES[decoded.errorName] ??
        `Transaction reverted: ${decoded.errorName}`
      );
    } catch {
      // Could not decode — fall through
    }
  }

  return undefined;
}

const MAX_ERROR_LENGTH = 120;

/** Truncate an error to a readable one-liner. */
export function formatError(err: unknown): string {
  if (!(err instanceof Error)) return String(err);
  const msg = err.message;
  return msg.length > MAX_ERROR_LENGTH
    ? msg.slice(0, MAX_ERROR_LENGTH) + "..."
    : msg;
}

/**
 * Trade error boundary for buy/sell commands.
 * Knows about viem errors and gives trade-specific guidance.
 */
export function tradeErrorMessage(err: unknown): string {
  if (!(err instanceof Error)) return String(err);

  if (err instanceof ViemBaseError) {
    const insufficient = err.walk((e) => e instanceof InsufficientFundsError);
    if (insufficient)
      return "Not enough funds. Try a lower amount or run 'zora balance spendable' to check your balance.";

    const decoded = decodeTradeRevert(err);
    if (decoded) return decoded;

    return err.shortMessage;
  }

  return apiErrorMessage(err);
}

/**
 * API/network error boundary for explore, get, balance.
 * Handles HTTP status codes and Node.js network errors.
 */
export function apiErrorMessage(err: unknown): string {
  if (!(err instanceof Error)) return String(err);

  const code = (err as NodeJS.ErrnoException).code;
  if (code === "ECONNREFUSED" || code === "ENOTFOUND")
    return "Can't connect. Check your internet connection.";
  if (code === "ETIMEDOUT" || code === "UND_ERR_CONNECT_TIMEOUT")
    return "Request timed out. Try again.";

  const status = (err as any).status;
  if (status === 429)
    return "Rate limited. Wait a moment or run 'zora auth configure' for higher limits.";
  if (status === 401 || status === 403)
    return "Auth failed. Run 'zora auth configure' to update your API key.";
  if (typeof status === "number" && status >= 500)
    return "Zora is temporarily unavailable. Try again later.";

  return formatError(err);
}

/**
 * Extract a human-readable message from an SDK response error object.
 * Handles both `{ error: "message" }` objects and raw values.
 */
export function extractErrorMessage(error: unknown): string {
  if (typeof error === "object" && error !== null && "error" in error) {
    return String((error as Record<string, unknown>).error);
  }
  return JSON.stringify(error);
}

/** A plain object safe to JSON.stringify and send over the wire. */
export type SerializableValue =
  | string
  | number
  | boolean
  | null
  | SerializableValue[]
  | { [key: string]: SerializableValue };

const MAX_SERIALIZE_DEPTH = 6;

/**
 * Convert an arbitrary value into a plain, JSON-serializable structure.
 *
 * - Drops cyclic references (replaced with "[Circular]").
 * - Reads through getters defensively; a throwing getter becomes "[Unserializable: ...]".
 * - Coerces non-JSON primitives (BigInt, Symbol, undefined, functions) into strings or drops them.
 * - Bounds recursion depth to avoid pathological/very deep structures.
 *
 * The result contains only string keys and JSON-serializable values — no live
 * getters, prototypes, or class instances survive.
 */
function toSerializable(
  value: unknown,
  seen: WeakSet<object>,
  depth: number,
): SerializableValue {
  if (value === null) return null;

  const type = typeof value;
  if (type === "string" || type === "boolean") {
    return value as string | boolean;
  }
  if (type === "number") {
    // NaN/Infinity are not valid JSON — coerce to null like JSON.stringify does.
    return Number.isFinite(value as number) ? (value as number) : null;
  }
  if (type === "bigint") return (value as bigint).toString();
  if (type === "undefined" || type === "function" || type === "symbol") {
    // These have no JSON representation; callers strip them out at the object level.
    return null;
  }

  // Objects from here down.
  const obj = value as object;

  if (seen.has(obj)) return "[Circular]";
  if (depth >= MAX_SERIALIZE_DEPTH) return "[MaxDepth]";

  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.toISOString();
  }

  seen.add(obj);
  try {
    if (Array.isArray(value)) {
      return value.map((item) => toSerializable(item, seen, depth + 1));
    }

    // Errors don't expose name/message/stack as own enumerable props, so pull
    // them explicitly before walking the remaining own enumerable keys.
    const result: { [key: string]: SerializableValue } = {};
    if (value instanceof Error) {
      result.name = value.name;
      result.message = value.message;
      if (value.stack) result.stack = value.stack;
    }

    for (const key of Object.keys(value as Record<string, unknown>)) {
      if (key in result) continue;
      let raw: unknown;
      try {
        raw = (value as Record<string, unknown>)[key];
      } catch (getterError) {
        result[key] =
          `[Unserializable: ${getterError instanceof Error ? getterError.message : String(getterError)}]`;
        continue;
      }
      // Skip keys that carry no JSON value rather than emitting nulls for them.
      const t = typeof raw;
      if (t === "undefined" || t === "function" || t === "symbol") continue;
      result[key] = toSerializable(raw, seen, depth + 1);
    }
    return result;
  } finally {
    seen.delete(obj);
  }
}

/**
 * Build a plain, JSON-serializable object from an error (or any unknown value)
 * suitable for sending in an HTTP POST body.
 *
 * Guarantees: no cyclic references, no live getters, only string keys and
 * JSON-serializable values. Always returns an object (primitives are wrapped
 * under a `message` key) so the payload shape is predictable for consumers.
 */
export function serializeError(err: unknown): {
  [key: string]: SerializableValue;
} {
  const serialized = toSerializable(err, new WeakSet(), 0);
  if (serialized !== null && typeof serialized === "object") {
    if (Array.isArray(serialized)) return { value: serialized };
    return serialized;
  }
  // Primitive (string/number/bool/null) — wrap so the payload is always an object.
  return { message: serialized === null ? String(err) : serialized };
}

export function bannedCoinMessage(address: string): string {
  return `The coin at ${address} is unavailable because it violates the Zora terms of service.`;
}

export function bannedCoinBuyMessage(address: string): string {
  return `Unable to buy ${address} because it violates the Zora terms of service. Already own this coin? Run zora sell ${address} --all to exit your position.`;
}

export function bannedProfileMessage(identifier: string): string {
  return `This account (${identifier}) has been blocked for violating the Zora terms of service.`;
}

/**
 * Filesystem error boundary for auth, setup, config.
 * Gives actionable messages for permission/path issues.
 */
export function fsErrorMessage(err: unknown, path: string): string {
  if (!(err instanceof Error)) return String(err);

  const code = (err as NodeJS.ErrnoException).code;
  if (code === "EACCES") return `Permission denied accessing ${path}.`;
  if (code === "EISDIR")
    return `Expected a file but found a directory at ${path}.`;

  return formatError(err);
}
