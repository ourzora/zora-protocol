import type { LocalAccount } from "viem";
import { trpcRequest, type ChainClient } from "./zora-client.js";
import type { RawUserOperation } from "./user-op.js";
import { signSimulateSubmit, type FinalizeResult } from "./submit.js";

/**
 * Create the agent's creator coin: build the (sponsored) deploy UserOp, then sign
 * it with the external EOA owner and submit. The coin's name/ticker come from the
 * agent's username server-side. With `dryRun`, stops after a successful simulation.
 */
export async function createCreatorCoin(params: {
  token: string;
  account: LocalAccount;
  client: ChainClient;
  dryRun: boolean;
}): Promise<FinalizeResult> {
  const { token, account, client, dryRun } = params;
  const { data, error } = await trpcRequest(
    token,
    "create.createDeployCreatorCoinUserOperation",
    {
      json: {},
    },
  );
  if (!data) {
    throw new Error(
      `createDeployCreatorCoinUserOperation failed: ${error ?? "no UserOp returned"}`,
    );
  }
  return signSimulateSubmit({
    token,
    account,
    client,
    raw: data as RawUserOperation,
    dryRun,
  });
}
