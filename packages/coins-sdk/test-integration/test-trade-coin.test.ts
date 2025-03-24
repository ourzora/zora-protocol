import { describe, it, beforeEach, expect } from "vitest";
import { getCoinState, tradeCoin } from "../src";

import {
  Address,
  Chain,
  LocalAccount,
  WalletClient,
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";
import { BuyEventArgs } from "../src/actions/tradeCoin";

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

  it("trades an existing coin", async () => {
    const coinAddress = "0x6349788903dbc2ad6fb5e4e09e656850b8c21e9f";
    // first buy
    const buyResponse = await tradeCoin(
      {
        target: coinAddress,
        direction: "buy",
        args: {
          recipient: walletClient.account!.address,
          orderSize: parseEther("0.000001"),
        },
      },
      walletClient,
      publicClient,
    );
    expect(buyResponse).toBeDefined();
    console.log({ buyResponse });
    expect((buyResponse.trade as BuyEventArgs).amountSold).toBeGreaterThan(
      1000,
    );
    expect((buyResponse.trade as BuyEventArgs).coinsPurchased).toBeGreaterThan(
      1000,
    );
    expect(buyResponse.trade?.recipient).toBeDefined();
    console.log({ buyResponse });

    const coinState = await getCoinState({
      coin: coinAddress,
      user: walletClient.account!.address,
      publicClient,
    });

    expect(coinState.balance).toBeGreaterThan(1000);

    // then sell
    const sellResponse = await tradeCoin(
      {
        target: coinAddress,
        direction: "sell",
        args: {
          recipient: walletClient.account!.address,
          orderSize: coinState.balance,
        },
      },
      publicClient,
      walletClient,
    );
    console.log({ sellResponse });
    expect(sellResponse).toBeDefined();
  });
});
