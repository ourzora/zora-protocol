import { Address } from "viem";
import { getPrivateKey, getSmartWalletAddress } from "../config.js";
import { formatError } from "../errors.js";
import { ERROR, safeExit } from "../exit.js";
import {
  createSmartWalletAccount,
  type SmartWalletAccount,
} from "./smart-wallet.js";
import { createPrivateKeyAccount, type PrivateKeyAccount } from "./wallet.js";

export { normalizeKey } from "./wallet.js";
export type { PrivateKeyAccount };
export type { SmartWalletAccount };

/**
 * Resolves a private key account and an optional smart wallet account from the environment or configuration file
 */
export const resolveAccount = async (
  json = false,
): Promise<{
  privateKeyAccount: PrivateKeyAccount;
  smartWalletAccount?: SmartWalletAccount;
}> => {
  let privateKey: string | undefined;
  let smartWalletAddress: Address | undefined;

  if (json) {
    privateKey = getPrivateKey();
    smartWalletAddress = getSmartWalletAddress();
  } else {
    // fallback to private key from config file if env var is not set
    privateKey = process.env.ZORA_PRIVATE_KEY ?? getPrivateKey();
  }

  if (!privateKey) {
    console.error(
      "No wallet configured. Run 'zora setup' to create or import one.",
    );
    return safeExit(ERROR);
  }

  let privateKeyAccount: PrivateKeyAccount | undefined;
  let smartWalletAccount: SmartWalletAccount | undefined;

  try {
    privateKeyAccount = createPrivateKeyAccount(privateKey);
  } catch (err) {
    console.error(`✗ Invalid private key: ${formatError(err)}`);
    console.error("  Run 'zora setup --force' to replace it.");
    return safeExit(ERROR);
  }

  try {
    if (smartWalletAddress) {
      smartWalletAccount = await createSmartWalletAccount({
        smartWalletAddress,
        privateKey,
      });
    }
  } catch (err) {
    console.error(
      `✗ Failed to setup smart wallet account: ${formatError(err)}`,
    );
    console.error(
      "  Ensure the smart wallet address is correct and the private key is a valid owner of the smart wallet.",
    );
    return safeExit(ERROR);
  }

  return { privateKeyAccount, smartWalletAccount };
};
