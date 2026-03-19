import { createPublicClient, createWalletClient, http } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { getPrivateKey } from "./config.js";
import { outputErrorAndExit } from "./output.js";

export const normalizeKey = (key: string): `0x${string}` =>
  (key.startsWith("0x") ? key : `0x${key}`) as `0x${string}`;

export const resolveAccount = (
  json = false,
): ReturnType<typeof privateKeyToAccount> => {
  const envKey = process.env.ZORA_PRIVATE_KEY;
  const key = envKey || getPrivateKey();

  if (!key) {
    outputErrorAndExit(
      json,
      "No wallet configured.",
      "Run 'zora setup' to create or import one.",
    );
  }

  try {
    return privateKeyToAccount(normalizeKey(key));
  } catch (err) {
    outputErrorAndExit(
      json,
      `Invalid private key: ${err instanceof Error ? err.message : String(err)}`,
      "Run 'zora setup --force' to replace it.",
    );
  }
};

export const createClients = (
  account: ReturnType<typeof privateKeyToAccount>,
) => {
  const publicClient = createPublicClient({
    chain: base,
    transport: http(),
  });

  const walletClient = createWalletClient({
    chain: base,
    transport: http(),
    account,
  });

  return { publicClient, walletClient };
};
