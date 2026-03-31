import { BaseError as ViemBaseError, InsufficientFundsError } from "viem";

/** Truncate an error to a readable one-liner. */
export function formatError(err: unknown): string {
  if (!(err instanceof Error)) return String(err);
  const msg = err.message;
  return msg.length > 120 ? msg.slice(0, 120) + "..." : msg;
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

export function bannedCoinMessage(address: string): string {
  return `The coin at ${address} is unavailable because it violates the Zora terms of service.`;
}

export function bannedCoinBuyMessage(address: string): string {
  return `Unable to buy ${address} because it violates the Zora terms of service. Already own this coin? Run zora sell ${address} --all to exit your position.`;
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
