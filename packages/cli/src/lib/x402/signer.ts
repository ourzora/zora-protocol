import type { Address } from "viem";
import type { ClientEvmSigner } from "@x402/evm";
import type { PrivateKeyAccount } from "../account/wallet.js";
import type { SmartWalletAccount } from "../account/smart-wallet.js";

/**
 * What the `pay` command signs with, plus how it should be reported.
 *
 * x402 v2's `ClientEvmSigner` only requires `address` + `signTypedData` for the
 * exact-EVM flow, which both a viem `PrivateKeyAccount` (EOA) and a Coinbase
 * smart wallet account satisfy directly — so unlike v1, no wrapper is needed.
 */
export type ResolvedX402Signer = {
  signer: ClientEvmSigner;
  address: Address;
  /** "smart-wallet" when funds are paid from the smart account, else "eoa". */
  walletType: "smart-wallet" | "eoa";
};

const toSigner = (
  account: PrivateKeyAccount | SmartWalletAccount,
): ClientEvmSigner => ({
  address: account.address,
  // viem's signTypedData is more strictly typed than x402's loose
  // {domain, types, primaryType, message}; the shapes are compatible at runtime.
  signTypedData: (message) =>
    account.signTypedData(
      message as Parameters<typeof account.signTypedData>[0],
    ),
});

/**
 * Choose the x402 signer. Prefers the smart wallet (where the agent holds its
 * funds) and falls back to the EOA. `forceEoa` pins to the EOA regardless.
 *
 * Because x402 settles a smart-wallet payment from the signing address, the
 * smart wallet must hold the asset. A facilitator that only accepts EOA
 * (ECDSA) signatures will reject the smart-wallet ERC-1271/6492 signature — use
 * `--eoa` in that case.
 */
export const resolveX402Signer = (
  privateKeyAccount: PrivateKeyAccount,
  smartWalletAccount: SmartWalletAccount | undefined,
  forceEoa = false,
): ResolvedX402Signer => {
  if (smartWalletAccount && !forceEoa) {
    return {
      signer: toSigner(smartWalletAccount),
      address: smartWalletAccount.address,
      walletType: "smart-wallet",
    };
  }

  return {
    signer: toSigner(privateKeyAccount),
    address: privateKeyAccount.address,
    walletType: "eoa",
  };
};
