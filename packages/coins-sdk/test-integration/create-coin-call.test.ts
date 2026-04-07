import { describe, expect } from "vitest";
import { createCoinCall } from "../src";
import { base } from "viem/chains";
import { Address, parseEther } from "viem";
import { makeAnvilTest, forkUrls } from "./util/anvil";
import { CreateConstants } from "../src/actions/createCoin";

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

      // Get the transaction parameters using createCoinCall
      const txCalls = await createCoinCall({
        creator: creatorAddress as Address,
        name: "Test Coin",
        symbol: "TEST",
        metadata: {
          type: "RAW_URI",
          uri: "ipfs://bafybeif47yyhfhcevqdnadyjdyzej3nuhggtbycerde4dg6ln46nnrykje",
        },
        currency: CreateConstants.ContentCoinCurrencies.ETH,
      });

      const tx = txCalls[0];

      // Simulate the call
      await publicClient.call({ ...tx, account: creatorAddress as Address });

      // Estimate gas and send
      const gas = await publicClient.estimateGas({
        ...tx,
        account: creatorAddress as Address,
      });
      const gasPrice = await publicClient.getGasPrice();
      const hash = await walletClient.sendTransaction({
        ...tx,
        gas,
        gasPrice,
        chain: publicClient.chain,
        account: creatorAddress as Address,
      });

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
          creator: creatorAddress as Address,
          name: "Test Coin",
          symbol: "TEST",
          metadata: {
            type: "RAW_URI",
            uri: "ipfs://bafybeibx5wpwwztdhoijwot2ja634kmtlnlzl5mjdk3gtibpf4cttwvhzq",
          },
          currency: CreateConstants.ContentCoinCurrencies.ETH,
          chainId: chain.id,
        }),
      ).rejects.toThrow(
        "Metadata is not a valid JSON or plain text response type",
      );
    },
    60_000, // Increase timeout to 60 seconds
  );
});
