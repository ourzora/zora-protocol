import {
  CustomTransport,
  createWalletClient as viemCreateWalletClient,
  WalletClient,
} from "viem";
import { base } from "viem/chains";
import type { PrivateKeyAccount } from "../account/wallet.js";
import { createCliRpcTransport } from "./rpc.js";

/**
 * Creates a viem wallet client for a private key account
 */
export const createWalletClient = (
  account: PrivateKeyAccount,
): WalletClient<CustomTransport, typeof base, PrivateKeyAccount> => {
  const chain = base;
  const transport = createCliRpcTransport(chain.id);

  return viemCreateWalletClient({
    chain,
    transport,
    account,
  });
};
