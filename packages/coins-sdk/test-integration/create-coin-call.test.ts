import { describe, expect, it } from "vitest";
import { createCoinCall } from "../src";
import { base } from "viem/chains";
import { Address, parseEther } from "viem";
import { makeAnvilTest, forkUrls } from "./util/anvil";
import { DeployCurrency } from "../src/actions/createCoin";

// Create a base mainnet anvil test instance
const baseAnvilTest = makeAnvilTest({
  forkUrl: forkUrls.base,
  forkBlockNumber: 31219478, // Using the same block as in create-coin-anvil.test.ts
  anvilChainId: base.id,
});

describe("Create Coin Call", () => {
  baseAnvilTest(
    "create coin call valid uri with simulateContract and writeContract",
    async ({ viemClients: { publicClient, walletClient, testClient } }) => {
      // Get test addresses
      const [creatorAddress] = await walletClient.getAddresses();
      expect(creatorAddress).toBeDefined();

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: creatorAddress as Address,
        value: parseEther("10"),
      });

      // Get the contract parameters using createCoinCall
      const createCoinRequest = await createCoinCall({
        name: "Test Coin",
        symbol: "TEST",
        uri: "ipfs://bafybeif47yyhfhcevqdnadyjdyzej3nuhggtbycerde4dg6ln46nnrykje",
        payoutRecipient: creatorAddress as Address,
        currency: DeployCurrency.ETH,
      });

      console.log("Contract request parameters:", createCoinRequest);

      // Simulate the contract call
      const { request } = await publicClient.simulateContract({
        ...createCoinRequest,
        account: creatorAddress,
      });

      // Add gas buffer (20%)
      if (request.gas) {
        request.gas = (request.gas * 120n) / 100n;
      }

      // Execute the contract call
      const hash = await walletClient.writeContract(request);

      // Wait for transaction confirmation
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      // Verify the result
      expect(receipt.status).toBe("success");
      expect(hash).toBeDefined();

      console.log("Transaction hash:", hash);
      console.log("Transaction receipt:", receipt);
    },
    60_000, // Increase timeout to 60 seconds
  );

  baseAnvilTest(
    "create coin call invalid uri",
    async ({ viemClients: { walletClient, testClient, chain } }) => {
      // Get test addresses
      const [creatorAddress] = await walletClient.getAddresses();
      expect(creatorAddress).toBeDefined();

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: creatorAddress as Address,
        value: parseEther("10"),
      });

      // Try to create a coin with invalid URI
      await expect(
        createCoinCall({
          name: "Test Coin",
          symbol: "TEST",
          // resolves to an image
          uri: "ipfs://bafybeibx5wpwwztdhoijwot2ja634kmtlnlzl5mjdk3gtibpf4cttwvhzq",
          owners: [creatorAddress as Address],
          payoutRecipient: creatorAddress as Address,
          chainId: chain.id,
          currency: DeployCurrency.ETH,
        }),
      ).rejects.toThrow(
        "Metadata is not a valid JSON or plain text response type",
      );
    },
    60_000, // Increase timeout to 60 seconds
  );
});
