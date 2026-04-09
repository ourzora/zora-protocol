import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createProgram } from "../test/create-program.js";

vi.mock("@zoralabs/coins-sdk");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
  getPrivateKey: vi.fn(),
}));
vi.mock("viem/accounts");
vi.mock("../lib/render.js", () => ({
  renderOnce: vi.fn(),
  renderLive: vi.fn(),
}));

vi.mock("viem", async (importOriginal) => {
  const actual = await importOriginal<typeof import("viem")>();
  return {
    ...actual,
    createPublicClient: vi.fn(() => ({
      getBalance: vi.fn().mockResolvedValue(1000000000000000000n), // 1 ETH
      multicall: vi.fn().mockResolvedValue([
        { status: "success", result: 5000000n }, // 5 USDC
        { status: "success", result: 5000000000000000000n }, // 5 ZORA
      ]),
    })),
  };
});

import {
  getProfileBalances,
  getTokenInfo,
  setApiKey,
} from "@zoralabs/coins-sdk";
import { getApiKey, getPrivateKey } from "../lib/config.js";
import { privateKeyToAccount } from "viem/accounts";
import { renderOnce, renderLive } from "../lib/render.js";
import { createPublicClient } from "viem";
import { balanceCommand } from "./balance.js";
import { buildProgram } from "../index.js";
import { renderToString } from "ink";

type TokenInfoQuery = { address: string; chainId?: number };

const tokenInfoImpl = ({ address }: TokenInfoQuery) => {
  if (address === "0x4200000000000000000000000000000000000006") {
    return Promise.resolve({
      data: {
        erc20Token: {
          currency: {
            priceUsd: "2500.00",
            decimals: 18,
            name: "Wrapped Ether",
            symbol: "WETH",
          },
        },
      },
    });
  }
  if (address === "0x1111111111166b7FE7bd91427724B487980aFc69") {
    return Promise.resolve({
      data: {
        erc20Token: {
          currency: {
            priceUsd: "0.005",
            decimals: 18,
            name: "ZORA",
            symbol: "ZORA",
          },
        },
      },
    });
  }
  return Promise.resolve({ data: null });
};

function setupTokenInfoMock() {
  vi.mocked(getTokenInfo).mockImplementation(tokenInfoImpl as never);
}

const coinBalancesPayload = {
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
};

const coinBalancesWithPageInfoPayload = {
  data: {
    profile: {
      coinBalances: {
        ...coinBalancesPayload.data.profile.coinBalances,
        pageInfo: { endCursor: "cursor_abc", hasNextPage: true },
      },
    },
  },
};

const emptyCoinsPayload = {
  data: {
    profile: {
      coinBalances: {
        count: 0,
        edges: [],
        pageInfo: { hasNextPage: false },
      },
    },
  },
};

describe("balance command", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;
  let errorSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    exitSpy = vi.spyOn(process, "exit").mockImplementation((code) => {
      throw new Error(`process.exit(${code})`);
    });

    vi.mocked(getApiKey).mockReturnValue("test-api-key");
    vi.mocked(getPrivateKey).mockReturnValue("0x" + "a".repeat(64));
    vi.mocked(privateKeyToAccount).mockReturnValue({
      address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
    } as never);

    setupTokenInfoMock();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    delete process.env.ZORA_PRIVATE_KEY;
  });

  function runBalance(args: string[] = []) {
    const program = createProgram(balanceCommand);
    return program.parseAsync(["balance", ...args], { from: "user" });
  }

  it("is wired into the root CLI program", async () => {
    const program = buildProgram();

    expect(program.commands.map((command) => command.name())).toContain(
      "balance",
    );
  });

  it("exits with error when no wallet is configured", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(undefined);

    await expect(runBalance()).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("No wallet configured"),
    );
  });

  it("outputs JSON with wallet and coins sections", async () => {
    vi.mocked(getProfileBalances).mockResolvedValue(
      coinBalancesPayload as never,
    );

    await runBalance(["--json"]);

    expect(logSpy).toHaveBeenCalledTimes(1);
    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));

    // Wallet section includes ETH, USDC, and ZORA (since mock returns >0)
    expect(output.wallet).toBeDefined();
    expect(output.wallet.length).toBeGreaterThanOrEqual(2);
    expect(output.wallet[0].symbol).toBe("ETH");
    expect(output.wallet[1].symbol).toBe("USDC");

    // Coins section
    expect(output.coins).toBeDefined();
    expect(output.coins[0]).toEqual({
      rank: 1,
      name: "Test Coin",
      symbol: "TEST",
      type: "post",
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
    });
  });

  it("renders two Ink table sections for static output", async () => {
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

    await runBalance(["--static"]);

    expect(setApiKey).toHaveBeenCalledWith("test-api-key");
    expect(renderOnce).toHaveBeenCalledTimes(1);
  });

  it("outputs correct JSON for large balances beyond MAX_SAFE_INTEGER", async () => {
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

    await runBalance(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    expect(output.coins[0].balance).toBe("3944403.815517124397199482");
    expect(output.coins[0].usdValue).toBeCloseTo(3944.4, 0);
  });

  it("outputs JSON with null fields when coin data is missing", async () => {
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

    await runBalance(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    expect(output.coins[0].name).toBeNull();
    expect(output.coins[0].symbol).toBeNull();
    expect(output.coins[0].priceUsd).toBeNull();
    expect(output.coins[0].usdValue).toBeNull();
    expect(output.coins[0].marketCap).toBeNull();
    expect(output.coins[0].marketCapChange24h).toBeNull();
  });

  it("exits with error when API returns an error response", async () => {
    vi.mocked(getProfileBalances).mockResolvedValue({
      error: { error: "Unauthorized" },
      data: null,
    } as never);

    await expect(runBalance(["--static"])).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("API error"));
  });

  it("exits with error when request throws", async () => {
    vi.mocked(getProfileBalances).mockRejectedValue(
      new Error("Network failure"),
    );

    await expect(runBalance(["--static"])).rejects.toThrow("process.exit(1)");
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining("Request failed: Network failure"),
    );
  });

  it("uses ZORA_PRIVATE_KEY env var when set", async () => {
    vi.mocked(getPrivateKey).mockReturnValue(undefined);
    process.env.ZORA_PRIVATE_KEY = "0x" + "b".repeat(64);
    vi.mocked(privateKeyToAccount).mockReturnValue({
      address: "0x1234567890abcdef1234567890abcdef12345678",
    } as never);

    vi.mocked(getProfileBalances).mockResolvedValue(emptyCoinsPayload as never);

    await runBalance(["--static"]);

    expect(privateKeyToAccount).toHaveBeenCalledWith("0x" + "b".repeat(64));
  });

  it("shows the empty-state hint when there are no coin balances", async () => {
    vi.mocked(getProfileBalances).mockResolvedValue(emptyCoinsPayload as never);

    await runBalance(["--static"]);

    expect(renderOnce).toHaveBeenCalled();
    const element = vi.mocked(renderOnce).mock.calls[0][0];
    const output = renderToString(element);
    expect(output).toContain("No coin balances found");
    expect(output).toContain("zora buy <address> --eth 0.001");
  });

  it("wallet JSON includes ETH price from tokenInfo", async () => {
    vi.mocked(getProfileBalances).mockResolvedValue(emptyCoinsPayload as never);

    await runBalance(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    const eth = output.wallet.find(
      (w: Record<string, unknown>) => w.symbol === "ETH",
    );
    expect(eth).toBeDefined();
    expect(eth.priceUsd).toBe(2500);
    expect(eth.usdValue).toBe(2500);
  });

  it("wallet JSON includes USDC with price of 1", async () => {
    vi.mocked(getProfileBalances).mockResolvedValue(emptyCoinsPayload as never);

    await runBalance(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    const usdc = output.wallet.find(
      (w: Record<string, unknown>) => w.symbol === "USDC",
    );
    expect(usdc).toBeDefined();
    expect(usdc.priceUsd).toBe(1);
  });

  it("omits USDC and ZORA from wallet when balances are zero", async () => {
    vi.mocked(createPublicClient).mockReturnValue({
      getBalance: vi.fn().mockResolvedValue(1000000000000000000n),
      multicall: vi.fn().mockResolvedValue([
        { status: "success", result: 0n }, // USDC = 0
        { status: "success", result: 0n }, // ZORA = 0
      ]),
    } as unknown as ReturnType<typeof createPublicClient>);

    vi.mocked(getProfileBalances).mockResolvedValue(emptyCoinsPayload as never);

    await runBalance(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    expect(output.wallet).toHaveLength(1);
    expect(output.wallet[0].symbol).toBe("ETH");
  });

  it("shows dash for USD value when price lookup fails", async () => {
    vi.mocked(getTokenInfo).mockRejectedValue(new Error("API down"));
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    vi.mocked(getProfileBalances).mockResolvedValue(emptyCoinsPayload as never);

    await runBalance(["--json"]);

    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    const eth = output.wallet.find(
      (w: Record<string, unknown>) => w.symbol === "ETH",
    );
    expect(eth.priceUsd).toBeNull();
    expect(eth.usdValue).toBeNull();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("failed to fetch price"),
    );
    warnSpy.mockRestore();
  });

  it("defaults to 0 balance when multicall fails for a token", async () => {
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});
    vi.mocked(createPublicClient).mockReturnValue({
      getBalance: vi.fn().mockResolvedValue(1000000000000000000n),
      multicall: vi.fn().mockResolvedValue([
        { status: "failure", error: new Error("reverted") },
        { status: "success", result: 5000000000000000000n },
      ]),
    } as unknown as ReturnType<typeof createPublicClient>);

    vi.mocked(getProfileBalances).mockResolvedValue(emptyCoinsPayload as never);

    await runBalance(["--json"]);

    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining("failed to fetch balance for USDC"),
    );
    const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
    // USDC should be omitted since its balance is 0 (failed) and only ETH is always shown
    const symbols = output.wallet.map((w: Record<string, unknown>) => w.symbol);
    expect(symbols).toContain("ETH");
    expect(symbols).toContain("ZORA");
    expect(symbols).not.toContain("USDC");
    warnSpy.mockRestore();
  });

  describe("spendable subcommand", () => {
    it("returns only wallet data in JSON", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        emptyCoinsPayload as never,
      );

      await runBalance(["spendable", "--json"]);

      expect(logSpy).toHaveBeenCalledTimes(1);
      const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
      expect(output.wallet).toBeDefined();
      expect(output.coins).toBeUndefined();
    });

    it("does not call getProfileBalances", async () => {
      await runBalance(["spendable", "--json"]);

      expect(getProfileBalances).not.toHaveBeenCalled();
    });
  });

  describe("coins subcommand", () => {
    it("returns only coins data in JSON", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        coinBalancesPayload as never,
      );

      await runBalance(["coins", "--json"]);

      expect(logSpy).toHaveBeenCalledTimes(1);
      const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
      expect(output.coins).toBeDefined();
      expect(output.wallet).toBeUndefined();
    });

    it("passes sortOption to getProfileBalances for --sort balance", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        emptyCoinsPayload as never,
      );

      await runBalance(["coins", "--sort", "balance", "--json"]);

      expect(getProfileBalances).toHaveBeenCalledWith(
        expect.objectContaining({ sortOption: "BALANCE" }),
      );
    });

    it("exits with error for invalid sort", async () => {
      await expect(runBalance(["coins", "--sort", "invalid"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --sort value"),
      );
    });

    it("exits with error for invalid limit", async () => {
      await expect(runBalance(["coins", "--limit", "25"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --limit value"),
      );
    });

    it("exits with error for zero or negative limit", async () => {
      await expect(runBalance(["coins", "--limit", "0"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --limit value"),
      );
    });

    it("exits with error for non-numeric limit", async () => {
      await expect(runBalance(["coins", "--limit", "abc"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(errorSpy).toHaveBeenCalledWith(
        expect.stringContaining("Invalid --limit value"),
      );
    });

    it("exits with error when API returns an error response", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue({
        error: { error: "Unauthorized" },
        data: null,
      } as never);

      await expect(runBalance(["coins", "--json"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(logSpy).toHaveBeenCalledWith(expect.stringContaining("API error"));
    });

    it("exits with error when request throws", async () => {
      vi.mocked(getProfileBalances).mockRejectedValue(
        new Error("Network failure"),
      );

      await expect(runBalance(["coins", "--json"])).rejects.toThrow(
        "process.exit(1)",
      );
      expect(logSpy).toHaveBeenCalledWith(
        expect.stringContaining("Network failure"),
      );
    });

    it("passes --after cursor to getProfileBalances", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        emptyCoinsPayload as never,
      );

      await runBalance(["coins", "--json", "--after", "abc123"]);

      expect(getProfileBalances).toHaveBeenCalledWith(
        expect.objectContaining({ after: "abc123" }),
      );
    });

    it("includes pageInfo in JSON output", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        coinBalancesWithPageInfoPayload as never,
      );

      await runBalance(["coins", "--json"]);

      const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
      expect(output.pageInfo).toEqual({
        endCursor: "cursor_abc",
        hasNextPage: true,
      });
      expect(output.coins).toHaveLength(1);
    });

    it("includes pageInfo null when not present in response", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        coinBalancesPayload as never,
      );

      await runBalance(["coins", "--json"]);

      const output = JSON.parse(String(logSpy.mock.calls[0]?.[0]));
      expect(output.pageInfo).toBeNull();
    });

    it("shows next page hint in table output when hasNextPage is true", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        coinBalancesWithPageInfoPayload as never,
      );

      await runBalance(["coins", "--static"]);

      expect(renderOnce).toHaveBeenCalled();
      const element = vi.mocked(renderOnce).mock.calls[0][0];
      const output = renderToString(element);
      expect(output).toContain("Next page");
      expect(output).toContain("--limit 10");
      expect(output).toContain("cursor_abc");
    });

    it("does not show next page hint when hasNextPage is false", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue({
        data: {
          profile: {
            coinBalances: {
              ...coinBalancesPayload.data.profile.coinBalances,
              pageInfo: { hasNextPage: false },
            },
          },
        },
      } as never);

      await runBalance(["coins", "--static"]);

      expect(renderOnce).toHaveBeenCalled();
      const element = vi.mocked(renderOnce).mock.calls[0][0];
      const output = renderToString(element);
      expect(output).not.toContain("Next page");
    });

    it("passes initialCursor to BalanceView in live mode", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        emptyCoinsPayload as never,
      );

      await runBalance(["coins", "--after", "some_cursor"]);

      expect(renderLive).toHaveBeenCalled();
      const element = vi.mocked(renderLive).mock.calls[0][0] as any;
      expect(element.props.initialCursor).toBe("some_cursor");
    });

    it("works with --sort and --after together", async () => {
      vi.mocked(getProfileBalances).mockResolvedValue(
        emptyCoinsPayload as never,
      );

      await runBalance([
        "coins",
        "--sort",
        "market-cap",
        "--after",
        "cursor_xyz",
        "--json",
      ]);

      expect(getProfileBalances).toHaveBeenCalledWith(
        expect.objectContaining({
          sortOption: "MARKET_CAP",
          after: "cursor_xyz",
        }),
      );
    });
  });
});
