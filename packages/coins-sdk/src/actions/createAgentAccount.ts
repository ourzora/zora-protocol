/**
 * Create a programmatic Zora agent account.
 *
 * The agent's EOA signs an EIP-712 typed-data payload proving wallet ownership;
 * the backend mutation `createAgentAccount` (gated on the operator's Zora API
 * key) verifies the signature, mints a Privy user with a synthesized email,
 * and creates a Zora account with `account_type=AGENT`.
 *
 * Cross-language note: the backend recovers this signature with
 * `eth_account.recover_message(encode_typed_data(...))`. viem's
 * `signTypedData` produces canonical v=27/28 signatures and encodes `bytes32`
 * from `0x`-prefixed 32-byte hex strings — both of which `eth_account` accepts
 * by default. The nonce is generated locally via `crypto.getRandomValues` and
 * must be exactly 32 bytes (66 chars including the `0x` prefix).
 */

import type { Account, Hex } from "viem";
import { base } from "viem/chains";

import {
  createAgentAccountMutation,
  type CreateAgentAccountResponse,
} from "../api/agent";

const SIGNATURE_TTL_SECONDS = 300;

const EIP712_DOMAIN = {
  name: "Zora Agent Account",
  version: "1",
  chainId: base.id,
} as const;

const CREATE_AGENT_ACCOUNT_TYPES = {
  CreateAgentAccount: [
    { name: "wallet", type: "address" },
    { name: "username", type: "string" },
    { name: "nonce", type: "bytes32" },
    { name: "issuedAt", type: "uint256" },
    { name: "expiresAt", type: "uint256" },
  ],
} as const;

export type CreateAgentAccountArgs = {
  account: Account;
  username: string;
  displayName?: string;
  bio?: string;
  avatarUri?: string;
  /**
   * Override the EIP-712 expiry window. Default 300 seconds; backend enforces a
   * maximum TTL of 600 seconds.
   */
  ttlSeconds?: number;
};

function randomNonce(): Hex {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  let hex = "0x";
  for (const b of bytes) hex += b.toString(16).padStart(2, "0");
  return hex as Hex;
}

export async function createAgentAccount(
  args: CreateAgentAccountArgs,
): Promise<CreateAgentAccountResponse> {
  if (!args.account.signTypedData) {
    throw new Error(
      "Agent account creation requires a viem Account with signTypedData",
    );
  }

  const ttl = args.ttlSeconds ?? SIGNATURE_TTL_SECONDS;
  const now = Math.floor(Date.now() / 1000);
  const nonce = randomNonce();

  const signature = (await args.account.signTypedData({
    domain: EIP712_DOMAIN,
    primaryType: "CreateAgentAccount",
    types: CREATE_AGENT_ACCOUNT_TYPES,
    message: {
      wallet: args.account.address,
      username: args.username,
      nonce,
      issuedAt: BigInt(now),
      expiresAt: BigInt(now + ttl),
    },
  })) as Hex;

  return await createAgentAccountMutation({
    walletAddress: args.account.address,
    username: args.username,
    signature,
    nonce,
    issuedAt: now,
    expiresAt: now + ttl,
    displayName: args.displayName,
    bio: args.bio,
    avatarUri: args.avatarUri,
  });
}
