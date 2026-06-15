import { formatEther, Hex } from "viem";
import type {
  BundlerClient,
  SmartAccount,
  UserOperation,
  UserOperationReceipt,
} from "viem/account-abstraction";
import { UserOperationCall } from "./calls";

// Coinbase Smart Wallet uses ERC-4337 entry point 0.6.
export type PreparedUserOperation = UserOperation<"0.6">;

/**
 * Prepares a user operation from a list of contract calls.
 * Returns a fully-populated UserOperation (gas estimated, nonce filled) with a
 * stub signature from gas estimation. Must be re-signed before submitting.
 */
export const prepareUserOperation = async ({
  bundlerClient,
  account,
  calls,
}: {
  bundlerClient: BundlerClient;
  account: SmartAccount;
  calls: readonly UserOperationCall[];
}): Promise<PreparedUserOperation> => {
  const prepared = await bundlerClient.prepareUserOperation({
    account,
    calls,
  });
  return prepared as PreparedUserOperation;
};

/**
 * Signs and submits a prepared user operation, then waits for the receipt.
 *
 * The prepared op carries a stub signature from gas estimation, so we re-sign
 * here before sending. Otherwise viem's sendUserOperation would forward the
 * stub and the bundler would reject it as invalid.
 */
export const submitUserOperation = async ({
  bundlerClient,
  account,
  userOperation,
}: {
  bundlerClient: BundlerClient;
  account: SmartAccount;
  userOperation: PreparedUserOperation;
}): Promise<UserOperationReceipt> => {
  let hash: Hex;
  const signature = await account.signUserOperation(userOperation);

  try {
    hash = await bundlerClient.sendUserOperation({
      account,
      ...userOperation,
      signature,
    });
  } catch (error) {
    // handle gas errors to provide better user feedback
    if (isGasError(error)) {
      throw new CoinbaseGasError(error);
    }
    throw error;
  }

  return bundlerClient.waitForUserOperationReceipt({ hash });
};

type CoinbaseBundlerError = {
  stack: string;
  message: string;
  cause: unknown;
  details: string;
  docsPath: string;
  shortMessage: string;
  version: string;
  name: string;
};

export class CoinbaseGasError extends Error {
  cause: unknown;
  details: string;
  required?: bigint;
  available?: bigint;
  constructor(error: CoinbaseBundlerError) {
    let message: string;
    let available: bigint | undefined;
    let required: bigint | undefined;

    const match = error.details.match(
      /precheck failed: sender balance and deposit together is (\d+)? but must be at least (\d+)? to pay for this operation/,
    );

    if (match) {
      available = match[1] ? BigInt(match[1]) : undefined;
      required = match[2] ? BigInt(match[2]) : undefined;

      if (available !== undefined && required !== undefined) {
        message = `Insufficient balance. You need at least ${formatEther(required)} ETH to pay for this operation, but you only have ${formatEther(available)} ETH.`;
      } else if (required !== undefined) {
        message = `Insufficient balance. Make sure you have at least ${formatEther(required)} ETH in your wallet.`;
      } else {
        message = `Insufficient balance. Make sure you have enough ETH to pay for this operation.`;
      }
    } else {
      message = error.details ?? error.message;
    }

    super(message);
    this.cause = error.cause;
    this.details = error.details;
    this.available = available;
    this.required = required;
  }
}

function isGasError(error: unknown): error is CoinbaseBundlerError {
  return (
    (error as CoinbaseBundlerError).details?.startsWith(
      "precheck failed: sender balance and deposit together is",
    ) ?? false
  );
}
