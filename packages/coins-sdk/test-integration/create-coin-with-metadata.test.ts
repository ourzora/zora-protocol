import { describe, expect } from "vitest";
import { base } from "viem/chains";
import { Address, parseEther } from "viem";
import { makeAnvilTest, forkUrls } from "./util/anvil";
import {
  createCoin,
  setApiKey,
  createMetadataBuilder,
  createZoraUploaderForCreator,
} from "../src";
import { ZORA_ADDRESS } from "../src/utils/poolConfigUtils";
import { testPng } from "./util/test-png";

// Create a base sepolia anvil test instance
const baseAnvilTest = makeAnvilTest({
  forkUrl: forkUrls.base,
  forkBlockNumber: 31219478,
  anvilChainId: base.id,
});

describe("Create ETH Coin on Base with metadata", () => {
  baseAnvilTest(
    "creates a new coin using ZORA on Base with metadata upload",
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

      setApiKey(process.env.VITE_ZORA_API_KEY!);

      const { createMetadataParameters } = await createMetadataBuilder()
        .withName("Test Base ZORA Coin")
        .withSymbol("TBZC")
        .withDescription("Test Description")
        .withImage(new File([testPng], "test.png", { type: "image/png" }))
        .upload(createZoraUploaderForCreator(creatorAddress as Address));

      // Create the coin
      const result = await createCoin(
        {
          ...createMetadataParameters,
          owners: [creatorAddress as Address],
          payoutRecipient: creatorAddress as Address,
          chainId: chain.id,
        },
        walletClient,
        publicClient,
        {
          account: creatorAddress as Address,
          gasMultiplier: 120, // 20% buffer on gas
        },
      );

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
});
