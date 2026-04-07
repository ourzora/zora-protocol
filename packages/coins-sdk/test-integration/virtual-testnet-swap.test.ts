import { describe, it, expect, beforeEach } from "vitest";
import { tradeCoin, TradeParameters } from "../src";
import {
  Address,
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  toHex,
  Client,
  Hex,
} from "viem";
import { base } from "viem/chains";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

type TSetBalanceParams = [addresses: Address[], value: Hex];
type TSetERC20BalanceParams = [
  addresses: Address,
  token: Address,
  balance: Hex,
];
type InputParams = { addresses: Hex[]; value: bigint };

export async function tenderlySetBalance(client: Client, params: InputParams) {
  return client.request<{
    method: "tenderly_setBalance";
    Parameters: TSetBalanceParams;
    ReturnType: Hex;
  }>({
    method: "tenderly_setBalance",
    params: [params.addresses, toHex(params.value)] as TSetBalanceParams,
  });
}

type TenderlySetERC20BalanceParams = {
  address: Address;
  token: Hex;
  balance: bigint;
};

export async function tenderlySetERC20Balance(
  client: Client,
  params: TenderlySetERC20BalanceParams,
) {
  return client.request<{
    method: "tenderly_setERC20Balance";
    Parameters: TSetERC20BalanceParams;
    ReturnType: Hex;
  }>({
    method: "tenderly_setERC20Balance",
    params: [
      params.token,
      params.address,
      toHex(params.balance),
    ] as TSetERC20BalanceParams,
  });
}
// Create a base mainnet anvil test instance
describe("Coin Trading Virtual Testnet", () => {
  let rpcUrl: string;
  let publicClient: any;
  let walletClient: any;
  let account: any;

  beforeEach(async () => {
    const envRpcUrl = process.env.VITE_TENDERLY_RPC_URL;
    if (!envRpcUrl) {
      throw new Error("VITE_TENDERLY_RPC_URL is not set");
    }
    rpcUrl = envRpcUrl;

    account = privateKeyToAccount(generatePrivateKey());
    publicClient = createPublicClient({
      chain: base,
      transport: http(rpcUrl),
    });
    walletClient = createWalletClient({
      account,
      chain: base,
      transport: http(rpcUrl),
    });

    // Fund the wallet with test ETH
    await tenderlySetBalance(walletClient, {
      addresses: [account.address],
      value: parseEther("10"),
    });
  }, 15_000);

  it("Buys a creator coin", async () => {
    const tradeParameters: TradeParameters = {
      sell: { type: "eth" },
      buy: {
        type: "erc20",
        address: "0x4e93a01c90f812284f71291a8d1415a904957156",
      },
      amountIn: parseEther("0.001111"),
      slippage: 0.4,
      sender: account.address,
    };
    await tradeCoin(tradeParameters, walletClient, account, publicClient);
  }, 15_000);

  it("buys a content coin backed my a creator coin", async () => {
    const tradeParameters: TradeParameters = {
      sell: { type: "eth" },
      buy: {
        type: "erc20",
        address: "0x4e93a01c90f812284f71291a8d1415a904957156",
      },
      amountIn: parseEther("1"),
      slippage: 0.4,
      sender: account.address,
    };
    await expect(
      tradeCoin(tradeParameters, walletClient, account, publicClient),
    ).resolves.not.toThrow();
  }, 15_000);

  it("trades USDC for ETH", async () => {
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
      tradeCoin(tradeParameters, walletClient, account, publicClient),
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

    await expect(
      tradeCoin(tradeParameters2, walletClient, account, publicClient),
    ).resolves.not.toThrow();

    console.log("USDC to ETH trade completed successfully");
  }, 60_000);

  it("trades between two ERC20 tokens", async () => {
    // Create new clients for this specific test
    const testWalletClient = createWalletClient({
      account,
      chain: base,
      transport: http(rpcUrl),
    });

    // Fund the wallet with test ETH
    await tenderlySetBalance(testWalletClient, {
      addresses: [account.address],
      value: parseEther("1.4"),
    });

    const tradeParameters: TradeParameters = {
      sell: {
        type: "eth",
      },
      buy: {
        type: "erc20",
        address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      },
      amountIn: parseEther("1"),
      slippage: 0.02,
      sender: account.address,
    };

    await tradeCoin(tradeParameters, testWalletClient, account, publicClient);

    // we now have USDC, want to buy Creator Coin
    const tradeParameters2: TradeParameters = {
      sell: {
        type: "erc20",
        address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      },
      buy: {
        type: "erc20",
        address: "0x9b13358e3a023507e7046c18f508a958cda75f54",
      },
      amountIn: parseEther("1"), // 1 USDC
      slippage: 0.02,
      sender: account.address,
    };

    await expect(
      tradeCoin(tradeParameters2, testWalletClient, account, publicClient),
    ).resolves.not.toThrow();

    console.log("USDC to WETH trade completed successfully");
  }, 60_000);
});
