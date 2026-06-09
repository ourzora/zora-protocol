import type { LocalAccount } from "viem";
import {
  BASE_CHAIN_ID,
  EXTERNAL_OWNER_INDEX,
  trpcRequest,
  type ChainClient,
} from "./zora-client.js";
import {
  isSponsored,
  parseUserOperation,
  signUserOp,
  simulateUserOp,
  type RawUserOperation,
} from "./user-op.js";

// superjson markers for the UserOp's bigint fields on submit.
const SUBMIT_META: { values: Record<string, string[]> } = {
  values: {
    "userOperation.nonce": ["bigint"],
    "userOperation.callGasLimit": ["bigint"],
    "userOperation.verificationGasLimit": ["bigint"],
    "userOperation.preVerificationGas": ["bigint"],
    "userOperation.maxFeePerGas": ["bigint"],
    "userOperation.maxPriorityFeePerGas": ["bigint"],
  },
};

export interface SubmittedUserOp {
  hash: string;
  success: boolean;
  reason?: string;
  /** Raw tx logs from submitUserOperation (used to resolve the deployed coin address). */
  logs?: unknown[];
}

export interface FinalizeResult {
  /** Whether the op was paymaster-sponsored. */
  sponsored: boolean;
  /** The `simulateHandleOp` outcome detail. */
  simulation: string;
  /** Present unless this was a dry run. */
  submitted?: SubmittedUserOp;
}

/**
 * Sign a built UserOp with the external EOA owner (#1), confirm it with
 * `simulateHandleOp`, then submit it via `submitUserOperation` (the backend wraps
 * the raw signature into the SignatureWrapper). With `dryRun`, stop after the
 * simulation succeeds — nothing is submitted on-chain.
 */
export async function signSimulateSubmit(params: {
  token: string;
  account: LocalAccount;
  client: ChainClient;
  raw: RawUserOperation;
  dryRun: boolean;
}): Promise<FinalizeResult> {
  const { token, account, client, raw, dryRun } = params;
  const op = parseUserOperation(raw);
  const { signature } = await signUserOp(account, op, BASE_CHAIN_ID);

  const sim = await simulateUserOp(client, op, EXTERNAL_OWNER_INDEX, signature);
  if (!sim.valid) {
    throw new Error(`UserOp would be rejected on-chain (${sim.detail}).`);
  }
  if (dryRun) {
    return { sponsored: isSponsored(op), simulation: sim.detail };
  }

  const { data, error } = await trpcRequest(
    token,
    "smartWallet.submitUserOperation",
    {
      json: {
        chainId: BASE_CHAIN_ID,
        userOperation: raw,
        signature,
        ownerIndex: EXTERNAL_OWNER_INDEX,
      },
      meta: SUBMIT_META,
    },
  );
  if (!data?.hash) {
    throw new Error(`submitUserOperation failed: ${error ?? "no result"}`);
  }
  // `!data.success` (not `=== false`) so an absent or null flag is treated as
  // failure too — never report a mint as successful when the on-chain outcome
  // is unknown (e.g. a partial body or a schema change that drops `success`).
  if (!data.success) {
    throw new Error(
      `UserOp reverted on-chain: ${data.reason ?? "unknown"} (tx ${data.hash})`,
    );
  }
  return {
    sponsored: isSponsored(op),
    simulation: sim.detail,
    submitted: {
      hash: data.hash,
      success: data.success,
      reason: data.reason,
      logs: Array.isArray(data.logs) ? data.logs : [],
    },
  };
}
