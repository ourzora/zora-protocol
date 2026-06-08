import { Hex, PrivateKeyAccount } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { InvalidPrivateKeyError } from "./error.js";

/**
 * Normalizes a private key to a hex string
 */
export const normalizeKey = (key: string): Hex =>
  key.startsWith("0x") ? (key as Hex) : `0x${key}`;

/**
 * Creates a viem private key account
 */
export const createPrivateKeyAccount = (
  privateKey: string,
): PrivateKeyAccount => {
  try {
    return privateKeyToAccount(normalizeKey(privateKey));
  } catch (err) {
    throw new InvalidPrivateKeyError(err instanceof Error ? err : undefined);
  }
};

export type { PrivateKeyAccount };
