import { describe, expect } from "vitest";
import { base } from "viem/chains";
import { Address, parseEther } from "viem";
import { makeAnvilTest, forkUrls } from "./util/anvil";
import { createCoin, CreateConstants } from "../src";
import { ZORA_ADDRESS } from "../src/utils/poolConfigUtils";

// Create a base sepolia anvil test instance
const baseAnvilTest = makeAnvilTest({
  forkUrl: forkUrls.base,
  forkBlockNumber: 31219478,
  anvilChainId: base.id,
});

describe("Create ETH Coin on Base", () => {
  baseAnvilTest(
    "creates a new coin using ETH on Base Sepolia",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Get test addresses
      const [creatorAddress] = await walletClient.getAddresses();
      expect(creatorAddress).toBeDefined();

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: creatorAddress as Address,
        value: parseEther("10"),
      });

      // Define coin parameters
      const coinName = "Test Base Sepolia Coin";
      const coinSymbol = "TBSC";
      const coinUri =
        "ipfs://bafybeif47yyhfhcevqdnadyjdyzej3nuhggtbycerde4dg6ln46nnrykje";

      // Create the coin
      const result = await createCoin({
        call: {
          creator: creatorAddress as Address,
          name: coinName,
          symbol: coinSymbol,
          metadata: { type: "RAW_URI", uri: coinUri },
          currency: CreateConstants.ContentCoinCurrencies.ETH,
          chainId: chain.id,
        },
        walletClient,
        publicClient,
        options: {
          account: creatorAddress as Address,
          gasMultiplier: 120, // 20% buffer on gas
        },
      });

      // Verify the result
      expect(result.hash).toBeDefined();
      expect(result.receipt.status).toBe("success");
      expect(result.address).toBeDefined();

      // Additional verification if needed
      if (result.address) {
        // Check if the coin exists on chain
        const exists = await publicClient.getCode({
          address: result.address,
        });
        expect(exists).not.toBe("0x");

        console.log("Deployed coin address:", result.address);
        console.log("Transaction hash:", result.hash);
      }
    },
    60_000, // Increase timeout to 60 seconds
  );
  baseAnvilTest(
    "creates a new coin using ZORA on Base Sepolia",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Get test addresses
      const [creatorAddress] = await walletClient.getAddresses();
      expect(creatorAddress).toBeDefined();

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: creatorAddress as Address,
        value: parseEther("10"),
      });

      // Define coin parameters
      const coinName = "Test Base ZORA Coin";
      const coinSymbol = "TBZC";
      const coinUri =
        "ipfs://bafybeif47yyhfhcevqdnadyjdyzej3nuhggtbycerde4dg6ln46nnrykje";

      // Create the coin
      const result = await createCoin({
        call: {
          creator: creatorAddress as Address,
          name: coinName,
          symbol: coinSymbol,
          metadata: { type: "RAW_URI", uri: coinUri },
          currency: CreateConstants.ContentCoinCurrencies.ZORA,
          chainId: chain.id,
        },
        walletClient,
        publicClient,
        options: {
          account: creatorAddress as Address,
          gasMultiplier: 120, // 20% buffer on gas
        },
      });

      // Verify the result
      expect(result.hash).toBeDefined();
      expect(result.receipt.status).toBe("success");
      expect(result.address).toBeDefined();

      expect(result.deployment?.currency.toLowerCase()).toBe(
        ZORA_ADDRESS.toLowerCase(),
      );

      // Additional verification if needed
      if (result.address) {
        // Check if the coin exists on chain
        const exists = await publicClient.getCode({
          address: result.address,
        });
        expect(exists).not.toBe("0x");

        console.log("Deployed coin address:", result.address);
        console.log("Transaction hash:", result.hash);
      }
    },
    60_000, // Increase timeout to 60 seconds
  );
  baseAnvilTest(
    "creates a new coin using ZORA on Base (no pre-purchase)",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      const [creatorAddress] = await walletClient.getAddresses();
      expect(creatorAddress).toBeDefined();

      await testClient.setBalance({
        address: creatorAddress as Address,
        value: parseEther("10"),
      });

      const coinName = "Test Base ZORA Coin";
      const coinSymbol = "TBZC";
      const coinUri =
        "ipfs://bafybeif47yyhfhcevqdnadyjdyzej3nuhggtbycerde4dg6ln46nnrykje";

      const result = await createCoin({
        call: {
          creator: creatorAddress as Address,
          name: coinName,
          symbol: coinSymbol,
          metadata: { type: "RAW_URI", uri: coinUri },
          currency: CreateConstants.ContentCoinCurrencies.ZORA,
          chainId: chain.id,
        },
        walletClient,
        publicClient,
        options: {
          account: creatorAddress as Address,
          gasMultiplier: 120, // 20% buffer on gas
        },
      });

      expect(result.hash).toBeDefined();
      expect(result.receipt.status).toBe("success");
      expect(result.address).toBeDefined();
    },
    60_000, // Increase timeout to 60 seconds
  );
});
