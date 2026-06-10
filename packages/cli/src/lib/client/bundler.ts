import { apiUrl } from "@zoralabs/coins-sdk";
import type { HttpTransport } from "viem";
import { http } from "viem";
import {
  BundlerClient,
  createBundlerClient as viemCreateBundlerClient,
} from "viem/account-abstraction";
import { estimateFeesPerGas } from "viem/actions";
import { base } from "viem/chains";
import type { SmartWalletAccount } from "../account/smart-wallet.js";

// default 250ms matches Base's ~200ms preconf block time for fast receipt detection
const BUNDLER_POLLING_INTERVAL_MS = 250;

// Buffer applied to Base's live fee estimate when reserving the user operation
// prefund. A buffer absorbs fee movement between preparation and inclusion; 2x
// matches viem's own default buffer.
const FEE_BUFFER_MULTIPLIER = 2n;

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
    userOperation: {
      // Without this hook, viem floors maxFeePerGas at 3 gwei, which on Base
      // over-reserves the prefund by ~30-300x and makes funded smart wallets
      // fail the bundler's balance precheck. Use Base's live fee estimate with
      // a modest buffer so the reserved prefund tracks actual gas cost.
      estimateFeesPerGas: async () => {
        const { maxFeePerGas, maxPriorityFeePerGas } = await estimateFeesPerGas(
          smartWalletAccount.client,
          { chain: base, type: "eip1559" },
        );
        return {
          maxFeePerGas: maxFeePerGas * FEE_BUFFER_MULTIPLIER,
          maxPriorityFeePerGas,
        };
      },
    },
  });
};
