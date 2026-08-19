import {
  CustomTransport,
  HttpTransport,
  PublicClient,
  WalletClient,
} from "viem";
import { BundlerClient } from "viem/account-abstraction";
import { base } from "viem/chains";
import type { SmartWalletAccount } from "../account/smart-wallet.js";
import type { PrivateKeyAccount } from "../account/wallet.js";
import { createBundlerClient } from "./bundler.js";
import { createPublicClient } from "./public.js";
import { createWalletClient } from "./wallet.js";

type Chain = typeof base;

/**
 * Creates viem clients for a private key account and optionally a smart wallet account
 */
export function createClients(
  privateKeyAccount: PrivateKeyAccount,
  smartWalletAccount?: SmartWalletAccount,
): {
  publicClient: PublicClient<CustomTransport, Chain>;
  walletClient: WalletClient<CustomTransport, Chain, PrivateKeyAccount>;
  bundlerClient?: BundlerClient<HttpTransport, Chain, SmartWalletAccount>;
} {
  const publicClient = createPublicClient();
  const walletClient = createWalletClient(privateKeyAccount);
  const bundlerClient = smartWalletAccount
    ? createBundlerClient(smartWalletAccount)
    : undefined;

  return bundlerClient
    ? { publicClient, walletClient, bundlerClient }
    : { publicClient, walletClient };
}
