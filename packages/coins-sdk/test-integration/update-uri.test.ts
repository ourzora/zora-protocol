import { describe, it, beforeEach, expect } from "vitest";
import { updateCoinURI } from "../src";

import {
  Address,
  Chain,
  LocalAccount,
  WalletClient,
  createPublicClient,
  createWalletClient,
  http,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

const HTTP_RPC_URL = process.env.VITE_PUBLIC_RPC_URL!;

const publicClient = createPublicClient({
  chain: baseSepolia as Chain,
  transport: http(),
});

describe("Coin Trading", () => {
  let walletClient: WalletClient;
  let creatorAccount: LocalAccount;

  beforeEach(() => {
    if (!process.env.VITE_PRIVATE_KEY) {
      throw new Error("VITE_PRIVATE_KEY not set in environment");
    }
    creatorAccount = privateKeyToAccount(
      process.env.VITE_PRIVATE_KEY as Address,
    );
    console.log(`Setup wallet with ${creatorAccount.address}`);
    walletClient = createWalletClient({
      account: creatorAccount,
      transport: http(HTTP_RPC_URL),
    });
  });

  it("fails to update to a non-ipfs uri", async () => {
    const coinAddress = "0x6349788903dbc2ad6fb5e4e09e656850b8c21e9f";
    expect(() =>
      updateCoinURI(
        { coin: coinAddress, newURI: "asdf" },
        walletClient,
        publicClient,
      ),
    ).rejects.toThrowError();
  });

  it("updates the uri for an existing coin", async () => {
    const coinAddress = "0x6349788903dbc2ad6fb5e4e09e656850b8c21e9f";
    const response = await updateCoinURI(
      { coin: coinAddress, newURI: "ipfs://asdf" },
      walletClient,
      publicClient,
    );

    console.log(response);
  });
});
