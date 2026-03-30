import { describe, it, expect, vi } from "vitest";

vi.mock("@zoralabs/coins-sdk");

import { getCoin, getProfile, getTrend } from "@zoralabs/coins-sdk";
import {
  parseCoinRef,
  resolveCoin,
  parsePositionalCoinArgs,
  resolveAmbiguousName,
  coinArgsToRef,
  CoinArgError,
} from "./coin-ref.js";

describe("parseCoinRef", () => {
  it("parses 0x address", () => {
    expect(parseCoinRef("0xabcdef1234567890abcdef1234567890abcdef12")).toEqual({
      kind: "address",
      address: "0xabcdef1234567890abcdef1234567890abcdef12",
    });
  });

  it("parses short 0x prefix as address", () => {
    expect(parseCoinRef("0xabc")).toEqual({
      kind: "address",
      address: "0xabc",
    });
  });

  it("ignores --type for 0x address", () => {
    expect(parseCoinRef("0xabc", "creator-coin")).toEqual({
      kind: "address",
      address: "0xabc",
    });
  });

  it("parses creator-coin type", () => {
    expect(parseCoinRef("jacob", "creator-coin")).toEqual({
      kind: "prefixed",
      type: "creator-coin",
      name: "jacob",
    });
  });

  it("parses bare name as ambiguous", () => {
    expect(parseCoinRef("jacob")).toEqual({
      kind: "ambiguous",
      name: "jacob",
    });
  });
});

describe("parsePositionalCoinArgs", () => {
  it('returns typed for "creator-coin" + name', () => {
    expect(parsePositionalCoinArgs("creator-coin", "jacob")).toEqual({
      kind: "typed",
      type: "creator-coin",
      identifier: "jacob",
    });
  });

  it('returns typed for "trend" + name', () => {
    expect(parsePositionalCoinArgs("trend", "geese")).toEqual({
      kind: "typed",
      type: "trend",
      identifier: "geese",
    });
  });

  it("throws CoinArgError when creator-coin given without second arg", () => {
    expect(() => parsePositionalCoinArgs("creator-coin", undefined)).toThrow(
      CoinArgError,
    );

    try {
      parsePositionalCoinArgs("creator-coin", undefined);
    } catch (e) {
      expect(e).toBeInstanceOf(CoinArgError);
      expect((e as CoinArgError).message).toContain("Missing identifier");
      expect((e as CoinArgError).suggestion).toContain("creator-coin");
    }
  });

  it("throws CoinArgError when trend given without second arg", () => {
    expect(() => parsePositionalCoinArgs("trend", undefined)).toThrow(
      CoinArgError,
    );
  });

  it("returns address when firstArg starts with 0x", () => {
    expect(parsePositionalCoinArgs("0xabc", undefined)).toEqual({
      kind: "address",
      address: "0xabc",
    });
  });

  it("returns address and ignores secondArg when firstArg starts with 0x", () => {
    expect(parsePositionalCoinArgs("0xabc", "extra")).toEqual({
      kind: "address",
      address: "0xabc",
    });
  });

  it("returns ambiguous-name for a bare name", () => {
    expect(parsePositionalCoinArgs("alice", undefined)).toEqual({
      kind: "ambiguous-name",
      name: "alice",
    });
  });
});

describe("coinArgsToRef", () => {
  it("bridges typed to prefixed", () => {
    expect(
      coinArgsToRef({ kind: "typed", type: "creator-coin", identifier: "bob" }),
    ).toEqual({
      kind: "prefixed",
      type: "creator-coin",
      name: "bob",
    });
  });

  it("bridges typed trend to prefixed", () => {
    expect(
      coinArgsToRef({ kind: "typed", type: "trend", identifier: "geese" }),
    ).toEqual({
      kind: "prefixed",
      type: "trend",
      name: "geese",
    });
  });

  it("bridges address to address", () => {
    expect(coinArgsToRef({ kind: "address", address: "0xabc" })).toEqual({
      kind: "address",
      address: "0xabc",
    });
  });

  it("bridges ambiguous-name to ambiguous", () => {
    expect(coinArgsToRef({ kind: "ambiguous-name", name: "alice" })).toEqual({
      kind: "ambiguous",
      name: "alice",
    });
  });
});

describe("resolveAmbiguousName", () => {
  const creatorCoin = {
    name: "alice",
    address: "0xalice",
    coinType: "CREATOR",
    marketCap: "5000000",
    marketCapDelta24h: "100000",
    volume24h: "250000",
    uniqueHolders: 1000,
    createdAt: "2026-01-01T00:00:00Z",
    creatorAddress: "0xcreator",
    creatorProfile: { handle: "alice" },
  };

  const trendCoin = {
    name: "alice",
    address: "0xalicetrend",
    coinType: "TREND",
    marketCap: "3000000",
    marketCapDelta24h: "50000",
    volume24h: "100000",
    uniqueHolders: 500,
    createdAt: "2026-02-01T00:00:00Z",
  };

  it("returns ambiguous when both creator and trend are found", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "alice",
          creatorCoin: { address: "0xalice" },
        },
      },
    } as any);

    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: creatorCoin },
    } as any);

    vi.mocked(getTrend).mockResolvedValue({
      data: { trendCoin: trendCoin },
    } as any);

    const result = await resolveAmbiguousName("alice");

    expect(result.kind).toBe("ambiguous");
    if (result.kind === "ambiguous") {
      expect(result.creator.address).toBe("0xalice");
      expect(result.trend.address).toBe("0xalicetrend");
    }
  });

  it("returns found when only creator coin exists", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "alice",
          creatorCoin: { address: "0xalice" },
        },
      },
    } as any);

    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: creatorCoin },
    } as any);

    vi.mocked(getTrend).mockResolvedValue({
      error: { error: "not found" },
      data: undefined,
    } as any);

    const result = await resolveAmbiguousName("alice");

    expect(result.kind).toBe("found");
    if (result.kind === "found") {
      expect(result.coin.address).toBe("0xalice");
    }
  });

  it("returns found when only trend coin exists", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      error: { error: "not found" },
      data: undefined,
    } as any);

    vi.mocked(getTrend).mockResolvedValue({
      data: { trendCoin: trendCoin },
    } as any);

    const result = await resolveAmbiguousName("alice");

    expect(result.kind).toBe("found");
    if (result.kind === "found") {
      expect(result.coin.address).toBe("0xalicetrend");
    }
  });

  it("returns not-found when neither coin exists", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      error: { error: "not found" },
      data: undefined,
    } as any);

    vi.mocked(getTrend).mockResolvedValue({
      error: { error: "not found" },
      data: undefined,
    } as any);

    const result = await resolveAmbiguousName("nobody");

    expect(result.kind).toBe("not-found");
    if (result.kind === "not-found") {
      expect(result.message).toContain("nobody");
    }
  });
});

describe("resolveCoin", () => {
  it("resolves address to found coin", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "TestCoin",
          address: "0x1234",
          coinType: "CONTENT",
          marketCap: "5000000",
          marketCapDelta24h: "100000",
          volume24h: "250000",
          uniqueHolders: 1842,
          createdAt: "2026-03-01T14:30:00Z",
          creatorAddress: "0xcreator",
          creatorProfile: { handle: "alice" },
        },
      },
    } as any);

    const result = await resolveCoin({ kind: "address", address: "0x1234" });

    expect(getCoin).toHaveBeenCalledWith({ address: "0x1234" });
    expect(result).toEqual({
      kind: "found",
      coin: {
        name: "TestCoin",
        address: "0x1234",
        coinType: "post",
        marketCap: "5000000",
        marketCapDelta24h: "100000",
        volume24h: "250000",
        uniqueHolders: 1842,
        createdAt: "2026-03-01T14:30:00Z",
        creatorAddress: "0xcreator",
        creatorHandle: "alice",
      },
    });
  });

  it("returns not-found for address with no coin", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: { zora20Token: undefined },
    } as any);

    const result = await resolveCoin({ kind: "address", address: "0xdead" });
    expect(result.kind).toBe("not-found");
  });

  it("returns not-found when getCoin errors", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      error: { error: "not found" },
      data: undefined,
    } as any);

    const result = await resolveCoin({ kind: "address", address: "0xdead" });
    expect(result.kind).toBe("not-found");
  });

  it("resolves creator-coin by name via profile", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "jacob",
          creatorCoin: { address: "0xcoin123" },
        },
      },
    } as any);

    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "jacob",
          address: "0xcoin123",
          coinType: "CREATOR",
          marketCap: "8100000",
          marketCapDelta24h: "-280000",
          volume24h: "1200000",
          uniqueHolders: 12304,
          createdAt: "2026-01-20T11:15:00Z",
          creatorAddress: "0xjacob",
          creatorProfile: { handle: "jacob" },
        },
      },
    } as any);

    const result = await resolveCoin({
      kind: "prefixed",
      type: "creator-coin",
      name: "jacob",
    });

    expect(getProfile).toHaveBeenCalledWith({ identifier: "jacob" });
    expect(getCoin).toHaveBeenCalledWith({ address: "0xcoin123" });
    expect(result).toEqual({
      kind: "found",
      coin: expect.objectContaining({
        name: "jacob",
        coinType: "creator-coin",
        marketCap: "8100000",
      }),
    });
  });

  it("returns not-found when profile has no creator coin", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: { handle: "nocoin", creatorCoin: undefined },
      },
    } as any);

    const result = await resolveCoin({
      kind: "prefixed",
      type: "creator-coin",
      name: "nocoin",
    });
    expect(result.kind).toBe("not-found");
    if (result.kind === "not-found") {
      expect(result.message).toContain("does not have a creator coin");
    }
  });

  it("returns not-found when profile not found", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      error: { error: "not found" },
      data: undefined,
    } as any);

    const result = await resolveCoin({
      kind: "prefixed",
      type: "creator-coin",
      name: "nobody",
    });
    expect(result.kind).toBe("not-found");
    if (result.kind === "not-found") {
      expect(result.message).toContain("No creator found");
    }
  });

  it("resolves ambiguous name via profile (same as creator-coin)", async () => {
    vi.mocked(getProfile).mockResolvedValue({
      data: {
        profile: {
          handle: "alice",
          creatorCoin: { address: "0xalice" },
        },
      },
    } as any);

    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "alice",
          address: "0xalice",
          coinType: "CREATOR",
          marketCap: "1000000",
          marketCapDelta24h: "50000",
          volume24h: "200000",
          uniqueHolders: 500,
          createdAt: "2026-02-15T10:00:00Z",
        },
      },
    } as any);

    const result = await resolveCoin({ kind: "ambiguous", name: "alice" });

    expect(getProfile).toHaveBeenCalledWith({ identifier: "alice" });
    expect(result.kind).toBe("found");
  });

  it("maps TREND coinType correctly", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "geese",
          address: "0xtrend",
          coinType: "TREND",
          marketCap: "2300000",
          marketCapDelta24h: "200000",
          volume24h: "450000",
          uniqueHolders: 1842,
          createdAt: "2026-03-01T14:30:00Z",
        },
      },
    } as any);

    const result = await resolveCoin({ kind: "address", address: "0xtrend" });

    expect(result.kind).toBe("found");
    if (result.kind === "found") {
      expect(result.coin.coinType).toBe("trend");
    }
  });

  it("handles missing optional fields gracefully", async () => {
    vi.mocked(getCoin).mockResolvedValue({
      data: {
        zora20Token: {
          name: "MinimalCoin",
          address: "0xmin",
        },
      },
    } as any);

    const result = await resolveCoin({ kind: "address", address: "0xmin" });

    expect(result).toEqual({
      kind: "found",
      coin: {
        name: "MinimalCoin",
        address: "0xmin",
        coinType: "unknown",
        marketCap: "0",
        marketCapDelta24h: "0",
        volume24h: "0",
        uniqueHolders: 0,
        createdAt: undefined,
        creatorAddress: undefined,
        creatorHandle: undefined,
      },
    });
  });
});
