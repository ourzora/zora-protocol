import { Address, isAddress } from "viem";
import { getPrivateKey, getSmartWalletAddress } from "../config.js";
import { formatError } from "../errors.js";
import { ERROR, safeExit } from "../exit.js";
import {
  createSmartWalletAccount,
  type SmartWalletAccount,
} from "./smart-wallet.js";
import { createPrivateKeyAccount, type PrivateKeyAccount } from "./wallet.js";
import {
  handleAccountError,
  InvalidPrivateKeyError,
  InvalidSmartWalletAddressError,
  NoPrivateKeyError,
  NoSmartWalletAddressError,
} from "./error.js";

export { normalizeKey } from "./wallet.js";
export type { PrivateKeyAccount };
export type { SmartWalletAccount };

const resolvePrivateKey = (json = false) => {
  let privateKey: string | undefined;

  if (json) {
    privateKey = getPrivateKey();
  } else {
    // fallback to private key from config file if env var is not set
    privateKey = process.env.ZORA_PRIVATE_KEY ?? getPrivateKey();
  }

  if (!privateKey) {
    throw new NoPrivateKeyError();
  }

  return privateKey;
};

const resolveSmartWalletAddress = (json = false) => {
  let smartWalletAddress: Address | undefined;

  if (json) {
    smartWalletAddress = getSmartWalletAddress();
  } else {
    // fallback to smart wallet address from config file if env var is not set
    smartWalletAddress =
      (process.env.ZORA_SMART_WALLET_ADDRESS as Address | undefined) ??
      getSmartWalletAddress();
  }

  if (!smartWalletAddress) {
    throw new NoSmartWalletAddressError();
  }

  if (!isAddress(smartWalletAddress)) {
    throw new InvalidSmartWalletAddressError();
  }

  return smartWalletAddress;
};

/**
 * Resolves a private key account from the environment or configuration file
 *
 * Note: We leave this function intact with the pre-existing API for backwards compatibility
 */
export const resolveAccount = (json = false) => {
  try {
    const privateKey = resolvePrivateKey(json);
    const privateKeyAccount = createPrivateKeyAccount(privateKey);
    return privateKeyAccount;
  } catch (err) {
    const handled = handleAccountError(err);
    if (!handled) {
      console.error(`✗ Failed to resolve private key: ${formatError(err)}`);
      console.error("  Run 'zora setup --force' to replace it.");
    }
    // when the private key account is not resolved, exit with error
    return safeExit(ERROR);
  }
};

/**
 * Resolves a smart wallet account from the environment or configuration file
 */
export const resolveSmartWalletAccount = async (json = false) => {
  try {
    const privateKey = resolvePrivateKey(json);
    const smartWalletAddress = resolveSmartWalletAddress(json);
    const smartWalletAccount = await createSmartWalletAccount({
      smartWalletAddress,
      privateKey,
    });
    return smartWalletAccount;
  } catch (err) {
    const handled = handleAccountError(err);
    if (!handled) {
      console.error(`✗ Failed to resolve smart wallet: ${formatError(err)}`);
      console.error("  Run 'zora setup --force' to replace it.");
    }
    // when the smart wallet account is not resolved, exit with error
    return safeExit(ERROR);
  }
};

/**
 * Resolves a private key account and an optional smart wallet account from the environment or configuration file
 */
export const resolveAccounts = async (
  json = false,
): Promise<{
  privateKeyAccount: PrivateKeyAccount;
  smartWalletAccount: SmartWalletAccount | undefined;
}> => {
  let privateKeyAccount: PrivateKeyAccount | undefined;
  let smartWalletAddress: Address | undefined;
  let smartWalletAccount: SmartWalletAccount | undefined;

  // resolve the private key account - if this fails, the program will exit with an error
  privateKeyAccount = resolveAccount(json);

  // resolve the smart wallet address - if this fails, continue depending on the error
  try {
    smartWalletAddress = resolveSmartWalletAddress(json);
  } catch (err) {
    if (err instanceof NoSmartWalletAddressError) {
      // ignore when no smart wallet address is configured
      // this allows users to continue with EOA only mode
    } else {
      // if a smart wallet address is configured but invalid, exit with error
      const handled = handleAccountError(err);
      if (!handled) {
        console.error(`✗ Failed to resolve smart wallet: ${formatError(err)}`);
        console.error("  Run 'zora setup --force' to replace it.");
      }
      return safeExit(ERROR);
    }
  }

  // finally, if we have a smart wallet address, resolve the smart wallet account
  if (smartWalletAddress) {
    // resolve the smart wallet account - if this fails, exit with error
    smartWalletAccount = await resolveSmartWalletAccount(json);
  }

  return { privateKeyAccount, smartWalletAccount };
};
