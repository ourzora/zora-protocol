import { Address, isAddress } from "viem";
import { getPrivateKey, getSmartWalletAddress } from "../config.js";
import { formatError } from "../errors.js";
import { ERROR, safeExit } from "../exit.js";
import {
  handleAccountError,
  InvalidSmartWalletAddressError,
  NoPrivateKeyError,
  NoSmartWalletAddressError,
} from "./error.js";
import {
  createSmartWalletAccount,
  type SmartWalletAccount,
} from "./smart-wallet.js";
import { createPrivateKeyAccount, type PrivateKeyAccount } from "./wallet.js";

export { normalizeKey } from "./wallet.js";
export type { PrivateKeyAccount, SmartWalletAccount };

export const resolvePrivateKey = () => {
  // fallback to private key from config file if env var is not set
  const privateKey = process.env.ZORA_PRIVATE_KEY || getPrivateKey();

  if (!privateKey) {
    throw new NoPrivateKeyError();
  }

  return privateKey;
};

export const resolveSmartWalletAddress = () => {
  // fallback to smart wallet address from config file if env var is not set
  const smartWalletAddress =
    (process.env.ZORA_SMART_WALLET_ADDRESS as Address | undefined) ||
    getSmartWalletAddress();

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
 * Note:
 * We leave this function intact with the pre-existing API for backwards compatibility.
 * The json parameter has never been used and will be removed in a future release.
 *
 * @deprecated Use resolvePrivateKeyAccount instead to resolve a private key account specifically.
 * Alternatively, use resolveAccounts to resolve both a private key account and a smart wallet account.
 */
export const resolveAccount = (_json = false) => {
  return resolvePrivateKeyAccount();
};

/**
 * Resolves a private key account from the environment or configuration file
 */
export const resolvePrivateKeyAccount = () => {
  try {
    const privateKey = resolvePrivateKey();
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
export const resolveSmartWalletAccount = async () => {
  try {
    const privateKey = resolvePrivateKey();
    const smartWalletAddress = resolveSmartWalletAddress();
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
export const resolveAccounts = async (): Promise<{
  privateKeyAccount: PrivateKeyAccount;
  smartWalletAccount: SmartWalletAccount | undefined;
}> => {
  let privateKeyAccount: PrivateKeyAccount | undefined;
  let smartWalletAddress: Address | undefined;
  let smartWalletAccount: SmartWalletAccount | undefined;

  // resolve the private key account - if this fails, the program will exit with an error
  privateKeyAccount = resolvePrivateKeyAccount();

  // resolve the smart wallet address - if this fails, continue depending on the error
  try {
    smartWalletAddress = resolveSmartWalletAddress();
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
    smartWalletAccount = await resolveSmartWalletAccount();
  }

  return { privateKeyAccount, smartWalletAccount };
};
