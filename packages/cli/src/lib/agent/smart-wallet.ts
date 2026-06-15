import { encodeAbiParameters, type Address, type Hex } from "viem";
import {
  type ChainClient,
  BASE_CHAIN_ID,
  BASE_CHAIN_NAME,
  graphqlRequest,
  SMART_WALLET_NONCE,
  trpcRequest,
  ZORA_ACCOUNT_MANAGER,
} from "./zora-client.js";

const GET_ADDRESS_ABI = [
  {
    type: "function",
    name: "getAddress",
    stateMutability: "view",
    inputs: [
      { name: "owners", type: "bytes[]" },
      { name: "nonce", type: "uint256" },
    ],
    outputs: [{ type: "address" }],
  },
] as const;

const LINK_MUTATION =
  "mutation LinkSmartWallet($walletAddress: String!, $creationOwnerAddress: [String!]!, $deployedChain: EChainName!) {" +
  " linkSmartWallet(walletAddress: $walletAddress, creationOwnerAddress: $creationOwnerAddress, deployedChain: $deployedChain) { walletAddress } }";

const UPDATE_OWNERS_MUTATION =
  "mutation UpdateOwners($creationOwnerAddresses: [String!]!, $owners: [String!]!) {" +
  " updateSmartWalletCreationOwners(creationOwnerAddresses: $creationOwnerAddresses, owners: $owners) {" +
  " walletAddress smartWalletConfig { owners { ownerAddress ownerIndex } } } }";

export interface SmartWallet {
  address: Address;
  /** Creation owners in deploy order: index 0 = embedded (Privy), 1 = external EOA. */
  owners: Address[];
}

const encodeOwner = (owner: Address): Hex =>
  encodeAbiParameters([{ type: "address" }], [owner]);

/** Deterministic smart-wallet address for an owner set (via ZoraAccountManager). */
export async function predictAddress(
  client: ChainClient,
  owners: Address[],
): Promise<Address> {
  return client.readContract({
    address: ZORA_ACCOUNT_MANAGER,
    abi: GET_ADDRESS_ABI,
    functionName: "getAddress",
    args: [owners.map(encodeOwner), SMART_WALLET_NONCE],
  });
}

export async function isDeployed(
  client: ChainClient,
  address: Address,
): Promise<boolean> {
  const code = await client.getCode({ address });
  return Boolean(code) && code !== "0x";
}

export interface ProvisionOptions {
  token: string;
  client: ChainClient;
  /** The agent's embedded (Privy) wallet — owner #0. */
  embedded: Address;
  /** The agent's external EOA — owner #1, the headless signer. */
  external: Address;
  /** Link attempts; the deploy/index step can briefly race. */
  linkAttempts?: number;
  /** Attempts to poll for the on-chain deploy (it confirms asynchronously). */
  resolveAttempts?: number;
  sleep?: (ms: number) => Promise<void>;
}

/**
 * Provision the agent's smart wallet end-to-end:
 *   1. trigger the (sponsored) deploy via tRPC,
 *   2. resolve the deployed address on-chain (reads are gated headless),
 *   3. link it to the Zora account, and
 *   4. set owner indexes so the external EOA can sign UserOps as owner #1.
 *
 * Idempotent: re-running on an already-provisioned agent resolves + re-links the
 * same wallet.
 */
export async function provisionSmartWallet(
  opts: ProvisionOptions,
): Promise<SmartWallet> {
  const {
    token,
    client,
    embedded,
    external,
    linkAttempts = 4,
    resolveAttempts = 10,
  } = opts;
  const sleep =
    opts.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));

  // 1. Trigger the deploy. Its own link step can 500 on a deploy/index race; we
  //    re-link below, so a failure here is non-fatal — but keep the response so a
  //    genuine failure (expired token, 429, network) can be surfaced if step 2
  //    then finds nothing on-chain, instead of a generic "not found".
  const deploy = await trpcRequest(token, "smartWallet.createSmartWallet", {
    json: { chainId: BASE_CHAIN_ID },
  });

  // 2. Resolve the deployed wallet on-chain. The sponsored deploy confirms
  //    asynchronously, so poll until it appears. Prefer the two-owner wallet (the
  //    one the agent flow deploys, signable by the external EOA); fall back to the
  //    embedded-only candidate so we can report a clear error if that's all there is.
  let resolved: SmartWallet | undefined;
  for (let attempt = 0; attempt < resolveAttempts && !resolved; attempt++) {
    if (attempt > 0) await sleep(3000);
    for (const owners of [[embedded, external], [embedded]]) {
      const address = await predictAddress(client, owners);
      if (await isDeployed(client, address)) {
        resolved = { address, owners };
        break;
      }
    }
  }
  if (!resolved) {
    const deployNote = deploy.error
      ? ` The deploy request returned HTTP ${deploy.status}: ${deploy.error}`
      : "";
    throw new Error(
      `No deployed smart wallet found on-chain after polling — the sponsored deploy did not confirm.${deployNote}`,
    );
  }
  if (resolved.owners.length < 2) {
    throw new Error(
      "Smart wallet was deployed without the external EOA as an owner — it cannot sign UserOps headless.",
    );
  }

  // 3. Link (idempotent; retry the deploy/index race).
  for (let attempt = 0; attempt < linkAttempts; attempt++) {
    const { data, errors } = await graphqlRequest(
      token,
      LINK_MUTATION,
      "LinkSmartWallet",
      {
        walletAddress: resolved.address,
        creationOwnerAddress: resolved.owners,
        deployedChain: BASE_CHAIN_NAME,
      },
    );
    const message = errors?.[0]?.message ?? "";
    if (data?.linkSmartWallet || /already/i.test(message)) break;
    if (attempt === linkAttempts - 1) {
      throw new Error(`linkSmartWallet failed: ${message || "unknown error"}`);
    }
    await sleep(4000);
  }

  // 4. Set owner indexes (so submitUserOperation can target owner #1).
  const { errors } = await graphqlRequest(
    token,
    UPDATE_OWNERS_MUTATION,
    "UpdateOwners",
    {
      creationOwnerAddresses: resolved.owners,
      owners: resolved.owners,
    },
  );
  if (errors?.length) {
    throw new Error(
      `updateSmartWalletCreationOwners failed: ${errors[0]?.message}`,
    );
  }

  return resolved;
}
