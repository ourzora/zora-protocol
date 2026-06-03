import { Hex, PrivateKeyAccount } from "viem";
import { privateKeyToAccount } from "viem/accounts";

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
  return privateKeyToAccount(normalizeKey(privateKey));
};

export type { PrivateKeyAccount };
