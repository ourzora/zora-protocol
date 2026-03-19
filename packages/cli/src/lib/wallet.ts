import { createPublicClient, createWalletClient, http } from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { getPrivateKey } from "./config.js";

export function normalizeKey(key: string): `0x${string}` {
  return (key.startsWith("0x") ? key : `0x${key}`) as `0x${string}`;
}

export function resolveAccount(): ReturnType<typeof privateKeyToAccount> {
  const envKey = process.env.ZORA_PRIVATE_KEY;
  const key = envKey || getPrivateKey();

  if (!key) {
    console.error(
      "No wallet configured. Run 'zora setup' to create or import one.",
    );
    return process.exit(1);
  }

  try {
    return privateKeyToAccount(normalizeKey(key));
  } catch (err) {
    console.error(
      `✗ Invalid private key: ${err instanceof Error ? err.message : String(err)}`,
    );
    console.error("  Run 'zora setup --force' to replace it.");
    return process.exit(1);
  }
}

export function createClients(account: ReturnType<typeof privateKeyToAccount>) {
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
}
