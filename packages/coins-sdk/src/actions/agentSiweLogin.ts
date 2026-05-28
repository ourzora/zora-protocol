/**
 * Authenticate an agent account via SIWE (EIP-4361) and obtain a Privy JWT.
 *
 * The returned JWT can be passed to `setPrivyJwt(jwt)` so subsequent SDK
 * queries authenticate against Privy-gated Zora mutations (profile updates,
 * follow/block, DMs, etc.).
 *
 * Architecture: the SIWE round-trip is mediated by the Zora backend rather
 * than calling Privy directly from the SDK. The backend already has Privy
 * server-side integration (App Secret + the `PrivyUser` helpers), so we POST
 * `{message, signature}` to Zora's `agentSiweLogin` mutation, which validates
 * the signature, confirms the wallet maps to an agent account, and returns a
 * Privy access token. Avoids needing a Privy SDK in the CLI/SDK.
 *
 * SIWE config (domain, chainId format) mirrors the Zora frontend's
 * `useLinkWalletAndAddOwner` pattern so signatures produced here are
 * structurally identical to ones the frontend produces.
 */

import type { Account, Hex } from "viem";
import { base } from "viem/chains";
import { createSiweMessage } from "viem/siwe";

import {
  agentSiweLoginMutation,
  type AgentSiweLoginResponse,
} from "../api/agent";

const SIWE_DOMAIN = "zora.co";
const SIWE_URI = "https://zora.co";
const SIWE_STATEMENT = "Sign in to Zora as an agent.";

export type AgentSiweLoginArgs = {
  account: Account;
};

function randomNonceString(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let hex = "";
  for (const b of bytes) hex += b.toString(16).padStart(2, "0");
  return hex;
}

export async function agentSiweLogin(
  args: AgentSiweLoginArgs,
): Promise<AgentSiweLoginResponse> {
  if (!args.account.signMessage) {
    throw new Error(
      "Agent SIWE login requires a viem Account with signMessage",
    );
  }

  const message = createSiweMessage({
    domain: SIWE_DOMAIN,
    address: args.account.address,
    statement: SIWE_STATEMENT,
    uri: SIWE_URI,
    version: "1",
    chainId: base.id,
    nonce: randomNonceString(),
    issuedAt: new Date(),
  });

  const signature = (await args.account.signMessage({ message })) as Hex;

  return await agentSiweLoginMutation({
    walletAddress: args.account.address,
    message,
    signature,
  });
}
