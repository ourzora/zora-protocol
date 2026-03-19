import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";
import {
  formatBalance,
  formatUsdValue,
  normalizeTokenAmount,
  toHumanBalance,
} from "./balances.js";

vi.mock("@zoralabs/coins-sdk", () => ({
  setApiKey: vi.fn(),
  getProfileBalances: vi.fn(),
  getCoinsTopVolume24h: vi.fn(),
  getCoinsMostValuable: vi.fn(),
  getCoinsNew: vi.fn(),
  getCoinsTopGainers: vi.fn(),
  getCoinsLastTraded: vi.fn(),
  getCoinsLastTradedUnique: vi.fn(),
  getExploreTopVolumeAll24h: vi.fn(),
  getExploreTopVolumeCreators24h: vi.fn(),
  getExploreNewAll: vi.fn(),
  getExploreFeaturedCreators: vi.fn(),
  getExploreFeaturedVideos: vi.fn(),
  getCreatorCoins: vi.fn(),
  getMostValuableCreatorCoins: vi.fn(),
  getMostValuableAll: vi.fn(),
  getMostValuableTrends: vi.fn(),
  getNewTrends: vi.fn(),
  getTopVolumeTrends24h: vi.fn(),
  getTrendingAll: vi.fn(),
  getTrendingCreators: vi.fn(),
  getTrendingPosts: vi.fn(),
  getTrendingTrends: vi.fn(),
}));

vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
  getPrivateKey: vi.fn(),
}));

vi.mock("viem/accounts", () => ({
  privateKeyToAccount: vi.fn(),
}));

vi.mock("../lib/render.js", () => ({
  renderOnce: vi.fn(),
}));

describe("balances formatting", () => {
  it("converts raw balance to human-readable", () => {
    expect(toHumanBalance("1000000000000000000")).toBe(1);
    expect(toHumanBalance("500000000000000000")).toBe(0.5);
    expect(toHumanBalance("0")).toBe(0);
  });

  it("formats tiny USD balances as less than one cent", () => {
    // 0.001 tokens * $0.5 = $0.0005
    expect(formatUsdValue("1000000000000000", "0.5")).toBe("<$0.01");
  });

  it("formats USD value with 2 decimal places", () => {
    // 4 tokens * $0.05 = $0.20
    expect(formatUsdValue("4000000000000000000", "0.05")).toBe("$0.20");
  });

  it("formats missing token price as dash", () => {
    expect(formatUsdValue("2000000000000000000", undefined)).toBe("-");
  });

  it("formats zero balances", () => {
    expect(formatBalance("0")).toBe("0");
  });

  it("formats small balances with fixed decimals", () => {
    // 0.125 tokens in wei
    expect(formatBalance("125000000000000000")).toBe("0.1250");
  });

  it("formats large balances with compact long display", () => {
    // 20 million tokens in wei
    expect(formatBalance("20000000000000000000000000")).toMatch(/20 million/i);
  });

  it("normalizes raw token amounts without precision loss", () => {
    expect(normalizeTokenAmount("3944403815517124397199482")).toBe(
      "3944403.815517124397199482",
    );
    expect(normalizeTokenAmount("1000000000000000000")).toBe("1");
  });

  it("toHumanBalance handles balances beyond Number.MAX_SAFE_INTEGER", () => {
    // 3,944,403 tokens — raw value exceeds 2^53
    const raw = "3944403815517124397199482";
    const result = toHumanBalance(raw);
    // Must start with 3944403.8155... — Number() loses precision past ~16 digits
    // but the integer and early decimal portion must be correct
    expect(result).toBeCloseTo(3944403.8155, 3);
  });

  it("toHumanBalance preserves precision for values just above MAX_SAFE_INTEGER", () => {
    // 10,000 tokens = 10000 * 1e18, which is > Number.MAX_SAFE_INTEGER
    const raw = "10000000000000000000000";
    expect(toHumanBalance(raw)).toBe(10000);
  });

  it("formatBalance handles sub-0.001 balances", () => {
    // 0.0001 tokens
    expect(formatBalance("100000000000000")).toBe("<0.001");
  });

  it("formatBalance handles balances between 1 and 1000", () => {
    // 50 tokens
    expect(formatBalance("50000000000000000000")).toMatch(/50/);
  });

  it("formatUsdValue computes correctly for large balances", () => {
    // 10,000 tokens at $2 each = $20,000
    const raw = "10000000000000000000000";
    expect(formatUsdValue(raw, "2")).toBe("$20,000.00");
  });

  it("normalizeTokenAmount returns raw string for non-bigint input", () => {
    expect(normalizeTokenAmount("not-a-number")).toBe("not-a-number");
  });

  it("normalizeTokenAmount handles zero", () => {
    expect(normalizeTokenAmount("0")).toBe("0");
  });

  it("normalizeTokenAmount respects custom decimals", () => {
    // 1.5 with 6 decimals = 1500000
    expect(normalizeTokenAmount("1500000", 6)).toBe("1.5");
  });
});

describe("balances command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(async () => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    const { getApiKey, getPrivateKey } = await import("../lib/config.js");
    const { privateKeyToAccount } = await import("viem/accounts");

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getPrivateKey).mockReturnValue("0x" + "a".repeat(64));
    vi.mocked(privateKeyToAccount).mockReturnValue({
      address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
    } as never);
  });

  afterEach(() => {
    vi.restoreAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
  });

  async function runBalances(args: string[] = []) {
    const { balancesCommand } = await import("./balances.js");
    const program = createProgram(balancesCommand);
    await program.parseAsync(["balances", ...args], { from: "user" });
  }

  it("is wired into the root CLI program", async () => {
    const { buildProgram } = await import("../index.js");
    const program = buildProgram();

    expect(program.commands.map((command) => command.name())).toContain(
      "balances",
    );
  });

  it("exits with error for invalid sort", async () => {
    await expect(runBalances(["--sort", "invalid"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --sort value"),
    );
  });

  it("exits with error for invalid limit", async () => {
    await expect(runBalances(["--limit", "25"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --limit value"),
    );
  });

  it("exits with error when no API key is configured", async () => {
    const { getApiKey } = await import("../lib/config.js");
    vi.mocked(getApiKey).mockReturnValue(undefined);

    await expect(runBalances()).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Not authenticated"),
    );
  });

  it("outputs JSON with --json", async () => {
    const { getProfileBalances } = await import("@zoralabs/coins-sdk");

    vi.mocked(getProfileBalances).mockResolvedValue({
      data: {
        profile: {
          coinBalances: {
            count: 1,
            edges: [
              {
                node: {
                  balance: "12340000000000000000",
                  coin: {
                    address: "0x123",
                    name: "Test Coin",
                    symbol: "TEST",
                    coinType: "CONTENT",
                    chainId: 8453,
                    marketCap: "1000000",
                    marketCapDelta24h: "10000",
                    volume24h: "1200",
                    totalVolume: "5000",
                    tokenPrice: { priceInUsdc: "1.5" },
                    creatorProfile: { handle: "alice" },
                    mediaContent: {
                      previewImage: { medium: "https://example.com/image.jpg" },
                    },
                  },
                },
              },
            ],
          },
        },
      },
    } as never);

    await runBalances(["--json"]);

    expect(logSpy).toHaveBeenCalledTimes(1);
    expect(JSON.parse(String(logSpy.mock.calls[0]?.[0]))).toEqual([
      {
        rank: 1,
        name: "Test Coin",
        symbol: "TEST",
        coinType: "CONTENT",
        chainId: 8453,
        address: "0x123",
        creatorHandle: "alice",
        previewImage: "https://example.com/image.jpg",
        balance: "12.34",
        usdValue: 18.51,
        priceUsd: 1.5,
        marketCap: 1000000,
        marketCapDelta24h: 10000,
        marketCapChange24h: 1.0101,
        volume24h: 1200,
        totalVolume: 5000,
      },
    ]);
  });

  it("renders an Ink table for default output", async () => {
    const { getProfileBalances, setApiKey } =
      await import("@zoralabs/coins-sdk");
    const { renderOnce } = await import("../lib/render.js");

    vi.mocked(getProfileBalances).mockResolvedValue({
      data: {
        profile: {
          coinBalances: {
            count: 1,
            edges: [
              {
                node: {
                  balance: "12340000000000000000",
                  coin: {
                    name: "Test Coin",
                    symbol: "TEST",
                    marketCap: "1000000",
                    marketCapDelta24h: "1000",
                    tokenPrice: { priceInUsdc: "1.5" },
                  },
                },
              },
            ],
          },
        },
      },
    } as never);

    await runBalances();

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(renderOnce).toHaveBeenCalled();
  });

  it("outputs correct JSON for large balances beyond MAX_SAFE_INTEGER", async () => {
    const { getProfileBalances } = await import("@zoralabs/coins-sdk");

    vi.mocked(getProfileBalances).mockResolvedValue({
      data: {
        profile: {
          coinBalances: {
            count: 1,
            edges: [
              {
                node: {
                  balance: "3944403815517124397199482",
                  coin: {
                    address: "0xabc",
                    name: "Big Bag",
                    symbol: "BIG",
                    coinType: "CONTENT",
                    chainId: 8453,
                    tokenPrice: { priceInUsdc: "0.001" },
                  },
                },
              },
            ],
          },
        },
      },
    } as never);

    await runBalances(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    expect(output[0].balance).toBe("3944403.815517124397199482");
    expect(output[0].usdValue).toBeCloseTo(3944.4, 0);
  });

  it("outputs JSON with null fields when coin data is missing", async () => {
    const { getProfileBalances } = await import("@zoralabs/coins-sdk");

    vi.mocked(getProfileBalances).mockResolvedValue({
      data: {
        profile: {
          coinBalances: {
            count: 1,
            edges: [
              {
                node: {
                  balance: "1000000000000000000",
                  coin: {},
                },
              },
            ],
          },
        },
      },
    } as never);

    await runBalances(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    expect(output[0].name).toBeNull();
    expect(output[0].symbol).toBeNull();
    expect(output[0].priceUsd).toBeNull();
    expect(output[0].usdValue).toBeNull();
    expect(output[0].marketCap).toBeNull();
    expect(output[0].marketCapChange24h).toBeNull();
  });

  it("exits with error for zero or negative limit", async () => {
    await expect(runBalances(["--limit", "0"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --limit value"),
    );
  });

  it("exits with error for non-numeric limit", async () => {
    await expect(runBalances(["--limit", "abc"])).rejects.toThrow(
      "process.exit(1)",
    );
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Invalid --limit value"),
    );
  });

  it("exits with error when no wallet is configured", async () => {
    const { getPrivateKey } = await import("../lib/config.js");
    vi.mocked(getPrivateKey).mockReturnValue(undefined);

    await expect(runBalances()).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("No wallet configured"),
    );
  });

  it("exits with error when API returns an error response", async () => {
    const { getProfileBalances } = await import("@zoralabs/coins-sdk");

    vi.mocked(getProfileBalances).mockResolvedValue({
      error: { error: "Unauthorized" },
      data: null,
    } as never);

    await expect(runBalances()).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("API error"));
  });

  it("exits with error when request throws", async () => {
    const { getProfileBalances } = await import("@zoralabs/coins-sdk");

    vi.mocked(getProfileBalances).mockRejectedValue(
      new Error("Network failure"),
    );

    await expect(runBalances()).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Request failed: Network failure"),
    );
  });

  it("uses ZORA_PRIVATE_KEY env var when set", async () => {
    const { getProfileBalances } = await import("@zoralabs/coins-sdk");
    const { getPrivateKey } = await import("../lib/config.js");
    const { privateKeyToAccount } = await import("viem/accounts");

    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    process.env.ZORA_PRIVATE_KEY = "0x" + "b".repeat(64);
    vi.mocked(privateKeyToAccount).mockReturnValue({
      address: "0x1234567890abcdef1234567890abcdef12345678",
    } as never);

    vi.mocked(getProfileBalances).mockResolvedValue({
      data: { profile: { coinBalances: { count: 0, edges: [] } } },
    } as never);

    await runBalances();

    expect(privateKeyToAccount).toHaveBeenCalledWith("0x" + "b".repeat(64));
  });

  it("shows the empty-state hint when there are no balances", async () => {
    const { getProfileBalances } = await import("@zoralabs/coins-sdk");

    vi.mocked(getProfileBalances).mockResolvedValue({
      data: {
        profile: {
          coinBalances: {
            count: 0,
            edges: [],
          },
        },
      },
    } as never);

    await runBalances();

    const output = logSpy.mock.calls.map((call) => call[0]).join("\n");
    expect(output).toContain("No coin balances found");
    expect(output).toContain("zora buy <address> --eth 0.001");
  });
});
