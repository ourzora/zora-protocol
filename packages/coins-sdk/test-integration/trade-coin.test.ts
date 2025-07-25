import { describe, expect } from "vitest";
import { tradeCoin, TradeParameters } from "../src";
import { base } from "viem/chains";
import { parseEther } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { makeAnvilTest, forkUrls } from "./util/anvil";

// Create a base mainnet anvil test instance
const baseAnvilTest = makeAnvilTest({
  forkUrl: forkUrls.base,
  forkBlockNumber: 33342700,
  anvilChainId: base.id,
});

describe("Coin Trading", () => {
  baseAnvilTest(
    "purchases creator coin 0x4e93a01c90f812284f71291a8d1415a904957156",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Generate a random private key and create account
      const privateKey = generatePrivateKey();
      const traderAccount = privateKeyToAccount(privateKey);

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: traderAccount.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: { type: "eth" },
        buy: {
          type: "erc20",
          address: "0x4e93a01c90f812284f71291a8d1415a904957156",
        },
        amountIn: BigInt(0.001 * 10 ** 18),
        slippage: 0.8,
        sender: traderAccount.address,
        permitActiveSeconds: 20 * 60,
      };

      // tradeCoin returns void, so we just call it and expect no errors
      const result = await tradeCoin({
        tradeParameters,
        walletClient,
        account: traderAccount,
        publicClient,
      });
      console.log({ result });

      console.log("Trade completed successfully");
    },
    60_000,
  );

  baseAnvilTest(
    "buys creator coin 0x90f1d388b06494cc4b6a7663984e4bebdcabaa42",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Generate a random private key and create account
      const privateKey = generatePrivateKey();
      const traderAccount = privateKeyToAccount(privateKey);

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: traderAccount.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: { type: "eth" },
        buy: {
          type: "erc20",
          address: "0x90f1d388b06494cc4b6a7663984e4bebdcabaa42",
        },
        amountIn: BigInt(0.001 * 10 ** 18),
        slippage: 0.8,
        sender: traderAccount.address,
        permitActiveSeconds: 20 * 60,
      };

      // tradeCoin returns void, so we just call it and expect no errors
      const result = await tradeCoin({
        tradeParameters,
        walletClient,
        account: traderAccount,
        publicClient,
      });
      console.log({ result });

      console.log("Trade completed successfully");
    },
    60_000,
  );

  baseAnvilTest(
    "purchases 0xe6efa904d9dcf13961690ff52eab33a38bfa701c with ETH",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Generate a random private key and create account
      const privateKey = generatePrivateKey();
      const traderAccount = privateKeyToAccount(privateKey);

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: traderAccount.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: { type: "eth" },
        buy: {
          type: "erc20",
          address: "0xe6efa904d9dcf13961690ff52eab33a38bfa701c",
        },
        amountIn: BigInt(0.001 * 10 ** 18),
        slippage: 0.8,
        sender: traderAccount.address,
        permitActiveSeconds: 1000000,
      };

      // tradeCoin returns void, so we just call it and expect no errors
      const result = await tradeCoin({
        tradeParameters,
        walletClient,
        account: traderAccount,
        publicClient,
      });
      console.log({ result });

      console.log("Trade completed successfully");
    },
    60_000, // Increase timeout to 60 seconds
  );

  baseAnvilTest(
    "trades ETH for USDC",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Generate a random private key and create account
      const privateKey = generatePrivateKey();
      const traderAccount = privateKeyToAccount(privateKey);

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: traderAccount.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: { type: "eth" },
        buy: {
          type: "erc20",
          address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        }, // USDC on Base
        amountIn: BigInt(0.001 * 10 ** 18), // Smaller amount for testing
        slippage: 0.15,
        sender: traderAccount.address,
      };

      await expect(
        tradeCoin({
          tradeParameters,
          walletClient,
          account: traderAccount,
          publicClient,
        }),
      ).resolves.not.toThrow();

      console.log("ETH to USDC trade completed successfully");
    },
    60_000,
  );

  baseAnvilTest(
    "trades USDC for ETH",
    async ({
      viemClients: { publicClient, walletClient, testClient, account },
    }) => {
      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: account.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: { type: "eth" },
        buy: {
          type: "erc20",
          address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        }, // USDC on Base
        amountIn: parseEther("0.4"), // 1 USDC (6 decimals)
        slippage: 0.03,
        sender: account.address,
      };

      await expect(
        tradeCoin({
          tradeParameters,
          walletClient,
          account,
          publicClient,
        }),
      ).resolves.not.toThrow();

      const tradeParameters2: TradeParameters = {
        sell: {
          type: "erc20",
          address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        }, // USDC on Base
        buy: { type: "eth" },
        amountIn: BigInt(10 * 10 ** 6), // 1 USDC (6 decimals)
        slippage: 0.04,
        sender: account.address,
      };

      console.log("testing trading usdc for ETH");

      // await expect(
      await tradeCoin({
        tradeParameters: tradeParameters2,
        walletClient,
        account,
        publicClient,
      });
      // ).resolves.not.toThrow();

      console.log("USDC to ETH trade completed successfully");
    },
    60_000,
  );

  baseAnvilTest(
    "trades between two ERC20 tokens",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Generate a random private key and create account
      const privateKey = generatePrivateKey();
      const traderAccount = privateKeyToAccount(privateKey);

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: traderAccount.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: {
          type: "erc20",
          address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
        }, // USDC
        buy: {
          type: "erc20",
          address: "0x4200000000000000000000000000000000000006",
        }, // WETH
        amountIn: BigInt(1 * 10 ** 6), // 1 USDC
        slippage: 0.01,
        sender: traderAccount.address,
      };

      await expect(
        tradeCoin({
          tradeParameters,
          walletClient,
          account: traderAccount,
          publicClient,
        }),
      ).resolves.not.toThrow();

      console.log("USDC to WETH trade completed successfully");
    },
    60_000,
  );

  baseAnvilTest(
    "throws error for invalid slippage",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Generate a random private key and create account
      const privateKey = generatePrivateKey();
      const traderAccount = privateKeyToAccount(privateKey);

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: traderAccount.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: { type: "eth" },
        buy: {
          type: "erc20",
          address: "0xa3baacb8564f6fb564e79570afe357c374e9c7e5",
        },
        amountIn: BigInt(0.001 * 10 ** 18),
        slippage: 1.5, // Invalid slippage > 1
        sender: traderAccount.address,
      };

      await expect(
        tradeCoin({
          tradeParameters,
          walletClient,
          account: traderAccount,
          publicClient,
        }),
      ).rejects.toThrow("Slippage must be less than 1, max 0.99");
    },
    60_000,
  );

  baseAnvilTest(
    "throws error for zero amount",
    async ({
      viemClients: { publicClient, walletClient, testClient, chain },
    }) => {
      // Generate a random private key and create account
      const privateKey = generatePrivateKey();
      const traderAccount = privateKeyToAccount(privateKey);

      // Fund the wallet with test ETH
      await testClient.setBalance({
        address: traderAccount.address,
        value: parseEther("10"),
      });

      const tradeParameters: TradeParameters = {
        sell: { type: "eth" },
        buy: {
          type: "erc20",
          address: "0xa3baacb8564f6fb564e79570afe357c374e9c7e5",
        },
        amountIn: BigInt(0), // Zero amount
        slippage: 0.01,
        sender: traderAccount.address,
      };

      await expect(
        tradeCoin({
          tradeParameters,
          walletClient,
          account: traderAccount,
          publicClient,
        }),
      ).rejects.toThrow("Amount in must be greater than 0");
    },
    60_000,
  );
});
