import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { Address } from "viem";

vi.mock("@zoralabs/coins-sdk", () => ({
  getTokenInfo: vi.fn(),
}));

vi.mock("viem", async (importOriginal) => {
  const actual = await importOriginal<typeof import("viem")>();
  return {
    ...actual,
    createPublicClient: vi.fn(() => ({
      getBalance: vi.fn().mockResolvedValue(2000000000000000000n), // 2 ETH
      multicall: vi.fn().mockResolvedValue([
        { status: "success", result: 10000000n }, // 10 USDC
        { status: "success", result: 100000000000000000000n }, // 100 ZORA
      ]),
    })),
  };
});

import { getTokenInfo } from "@zoralabs/coins-sdk";
import { createPublicClient } from "viem";
import { fetchTokenPriceUsd, fetchWalletBalances } from "./wallet-balances.js";

const WALLET_ADDRESS = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045" as Address;
const WETH_ADDRESS = "0x4200000000000000000000000000000000000006";
const ZORA_ADDRESS = "0x1111111111166b7FE7bd91427724B487980aFc69";

function mockTokenInfo(addressPriceMap: Record<string, string | null>) {
  vi.mocked(getTokenInfo).mockImplementation(
    ({ address }: { address: string }) => {
      const price = addressPriceMap[address];
      if (price === null || price === undefined) {
        return Promise.resolve({ data: null });
      }
      return Promise.resolve({
        data: {
          erc20Token: {
            currency: { priceUsd: price },
          },
        },
      });
    },
  );
}

describe("fetchTokenPriceUsd", () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns numeric price when API returns priceUsd", async () => {
    vi.mocked(getTokenInfo).mockResolvedValue({
      data: {
        erc20Token: { currency: { priceUsd: "2500.50" } },
      },
    } as never);

    const price = await fetchTokenPriceUsd(WETH_ADDRESS);

    expect(price).toBe(2500.5);
  });

  it("passes address and chainId directly to getTokenInfo", async () => {
    vi.mocked(getTokenInfo).mockResolvedValue({
      data: { erc20Token: { currency: { priceUsd: "100" } } },
    } as never);

    await fetchTokenPriceUsd("0xabc", 1);

    expect(getTokenInfo).toHaveBeenCalledWith({
      address: "0xabc",
      chainId: 1,
    });
  });

  it("defaults chainId to BASE_CHAIN_ID (8453)", async () => {
    vi.mocked(getTokenInfo).mockResolvedValue({
      data: { erc20Token: { currency: { priceUsd: "100" } } },
    } as never);

    await fetchTokenPriceUsd("0xabc");

    expect(getTokenInfo).toHaveBeenCalledWith({
      address: "0xabc",
      chainId: 8453,
    });
  });

  it("returns null when API returns no priceUsd", async () => {
    vi.mocked(getTokenInfo).mockResolvedValue({
      data: { erc20Token: { currency: {} } },
    } as never);

    const price = await fetchTokenPriceUsd(WETH_ADDRESS);

    expect(price).toBeNull();
  });

  it("returns null when API returns null data", async () => {
    vi.mocked(getTokenInfo).mockResolvedValue({ data: null } as never);

    const price = await fetchTokenPriceUsd(WETH_ADDRESS);

    expect(price).toBeNull();
  });

  it("returns null and warns when API throws", async () => {
    vi.mocked(getTokenInfo).mockRejectedValue(new Error("Network error"));

    const price = await fetchTokenPriceUsd(WETH_ADDRESS);

    expect(price).toBeNull();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("failed to fetch price"),
    );
  });
});

describe("fetchWalletBalances", () => {
  let warnSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    mockTokenInfo({
      [WETH_ADDRESS]: "2500",
      [ZORA_ADDRESS]: "0.005",
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns ETH, USDC, and ZORA balances with USD values", async () => {
    const { walletBalances, walletBalancesJson } =
      await fetchWalletBalances(WALLET_ADDRESS);

    expect(walletBalances).toHaveLength(3);
    expect(walletBalances[0].symbol).toBe("ETH");
    expect(walletBalances[1].symbol).toBe("USDC");
    expect(walletBalances[2].symbol).toBe("ZORA");

    // ETH: 2 ETH * $2500 = $5000
    expect(walletBalancesJson[0].priceUsd).toBe(2500);
    expect(walletBalancesJson[0].usdValue).toBe(5000);

    // USDC: 10 USDC * $1 (fixed) = $10
    expect(walletBalancesJson[1].priceUsd).toBe(1);
    expect(walletBalancesJson[1].usdValue).toBe(10);

    // ZORA: 100 ZORA * $0.005 = $0.50
    expect(walletBalancesJson[2].priceUsd).toBe(0.005);
    expect(walletBalancesJson[2].usdValue).toBe(0.5);
  });

  it("always shows ETH even with zero balance", async () => {
    vi.mocked(createPublicClient).mockReturnValue({
      getBalance: vi.fn().mockResolvedValue(0n),
      multicall: vi.fn().mockResolvedValue([
        { status: "success", result: 0n },
        { status: "success", result: 0n },
      ]),
    } as unknown as ReturnType<typeof createPublicClient>);

    const { walletBalances } = await fetchWalletBalances(WALLET_ADDRESS);

    expect(walletBalances.length).toBeGreaterThanOrEqual(1);
    expect(walletBalances[0].symbol).toBe("ETH");
  });

  it("omits zero-balance ERC20 tokens", async () => {
    vi.mocked(createPublicClient).mockReturnValue({
      getBalance: vi.fn().mockResolvedValue(1000000000000000000n),
      multicall: vi.fn().mockResolvedValue([
        { status: "success", result: 0n }, // USDC = 0
        { status: "success", result: 0n }, // ZORA = 0
      ]),
    } as unknown as ReturnType<typeof createPublicClient>);

    const { walletBalances } = await fetchWalletBalances(WALLET_ADDRESS);

    expect(walletBalances).toHaveLength(1);
    expect(walletBalances[0].symbol).toBe("ETH");
  });

  it("uses fixed price for USDC instead of API lookup", async () => {
    await fetchWalletBalances(WALLET_ADDRESS);

    // getTokenInfo should be called for ETH (WETH) and ZORA, but not USDC
    const calls = vi.mocked(getTokenInfo).mock.calls;
    const calledAddresses = calls.map(
      (c) => (c[0] as { address: string }).address,
    );
    expect(calledAddresses).toContain(WETH_ADDRESS);
    expect(calledAddresses).toContain(ZORA_ADDRESS);
    expect(calledAddresses).not.toContain(
      "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    );
  });

  it("shows dash for USD value when price lookup fails", async () => {
    vi.mocked(getTokenInfo).mockRejectedValue(new Error("API down"));

    const { walletBalances, walletBalancesJson } =
      await fetchWalletBalances(WALLET_ADDRESS);

    const eth = walletBalances.find((w) => w.symbol === "ETH")!;
    expect(eth.usdValue).toBe("-");

    const ethJson = walletBalancesJson.find((w) => w.symbol === "ETH")!;
    expect(ethJson.priceUsd).toBeNull();
    expect(ethJson.usdValue).toBeNull();
  });

  it("sets address to null for native ETH in JSON output", async () => {
    const { walletBalancesJson } = await fetchWalletBalances(WALLET_ADDRESS);

    const eth = walletBalancesJson.find((w) => w.symbol === "ETH")!;
    expect(eth.address).toBeNull();

    const usdc = walletBalancesJson.find((w) => w.symbol === "USDC")!;
    expect(usdc.address).toBe("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913");
  });

  it("warns when multicall fails for a token", async () => {
    vi.mocked(createPublicClient).mockReturnValue({
      getBalance: vi.fn().mockResolvedValue(1000000000000000000n),
      multicall: vi.fn().mockResolvedValue([
        { status: "failure", error: new Error("reverted") },
        { status: "success", result: 5000000000000000000n },
      ]),
    } as unknown as ReturnType<typeof createPublicClient>);

    await fetchWalletBalances(WALLET_ADDRESS);

    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("failed to fetch balance for USDC"),
    );
  });
});
