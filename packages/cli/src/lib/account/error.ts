import { formatError } from "../errors.js";

export class NoPrivateKeyError extends Error {
  constructor() {
    super("No private key configured");
  }
}

export class InvalidPrivateKeyError extends Error {
  readonly cause?: Error;

  constructor(error?: Error) {
    super("Invalid private key" + (error?.message ? ": " + error.message : ""));
    this.cause = error;
  }
}

export class NoSmartWalletAddressError extends Error {
  constructor() {
    super("No smart wallet address configured");
  }
}

export class InvalidSmartWalletAddressError extends Error {
  readonly cause?: Error;

  constructor(error?: Error) {
    super(
      "Invalid smart wallet address" +
        (error?.message ? ": " + error.message : ""),
    );
    this.cause = error;
  }
}

/**
 * Handles account errors and returns true if the error was handled
 */
export const handleAccountError = (err: unknown): boolean => {
  let handled = false;

  // handle missing private key
  if (err instanceof NoPrivateKeyError) {
    console.error(
      "No wallet configured. Run 'zora setup' to create or import one. You can also configure a wallet using the ZORA_PRIVATE_KEY environment variable.",
    );
    handled = true;
  }
  // handle invalid private key
  if (err instanceof InvalidPrivateKeyError) {
    console.error(`✗ Invalid private key: ${formatError(err.cause ?? err)}`);
    console.error("  Run 'zora setup --force' to replace it.");
    handled = true;
  }
  // handle missing smart wallet address
  if (err instanceof NoSmartWalletAddressError) {
    console.error(
      "No smart wallet configured. Run 'zora setup' to create or import one. You can also configure a smart wallet using the ZORA_SMART_WALLET_ADDRESS environment variable.",
    );
    handled = true;
  }
  // handle invalid smart wallet address
  if (err instanceof InvalidSmartWalletAddressError) {
    console.error(
      `✗ Invalid smart wallet address: ${formatError(err.cause ?? err)}`,
    );
    console.error("  Run 'zora setup --force' to replace it.");
    handled = true;
  }

  return handled;
};
