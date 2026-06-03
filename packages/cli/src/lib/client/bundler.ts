import { apiUrl } from "@zoralabs/coins-sdk";
import type { HttpTransport } from "viem";
import { http } from "viem";
import {
  BundlerClient,
  createBundlerClient as viemCreateBundlerClient,
} from "viem/account-abstraction";
import { base } from "viem/chains";
import type { SmartWalletAccount } from "../account/smart-wallet.js";

// default 250ms matches Base's ~200ms preconf block time for fast receipt detection
const BUNDLER_POLLING_INTERVAL_MS = 250;

/**
 * Creates a Coinbase Bundler client for a smart wallet account
 */
export const createBundlerClient = (
  smartWalletAccount: SmartWalletAccount,
): BundlerClient<HttpTransport, typeof base, SmartWalletAccount> => {
  // the sdk apiUrl helper is used here to get the full URL of the cli-rpc-bundler endpoint
  // the actual endpoint is defined in the universal-api-public-api repository to prevent api key leakage
  const bundlerUrl = apiUrl("/cli-rpc-bundler");

  return viemCreateBundlerClient({
    account: smartWalletAccount,
    client: smartWalletAccount.client,
    name: "Coinbase Bundler",
    transport: http(bundlerUrl, {
      timeout: 30_000,
    }),
    pollingInterval: BUNDLER_POLLING_INTERVAL_MS,
  });
};
