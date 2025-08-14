import { describe, it, beforeEach, expect } from "vitest";
import { createCoin, CreateConstants } from "../src";

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

describe("Coin Creation", () => {
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

  it("creates a new coin", async () => {
    const response = await createCoin({
      call: {
        creator: creatorAccount.address as Address,
        name: "name",
        symbol: "symbol",
        metadata: {
          type: "RAW_URI",
          uri: "data:application/json;charset=utf-8;base64,eyJkZXNjcmlwdGlvbiI6ImhlbG8iLCJuYW1lIjoiaGVsbyJ9",
        },
        currency: CreateConstants.ContentCoinCurrencies.ETH,
        chainId: baseSepolia.id,
      },
      walletClient,
      publicClient,
    });

    expect(response.address).toBeDefined();
    expect(response.deployment).toBeDefined();
    expect(response.deployment!.coin).toMatch(/^0x[a-fA-F0-9]{40}$/);
    expect(response.deployment!.name).toBe("name");
    expect(response.deployment!.symbol).toBe("symbol");
    console.log("Created coin at address:", response.deployment?.coin);
  });
});
