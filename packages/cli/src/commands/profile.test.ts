import { describe, it, expect, vi } from "vitest";

vi.mock("@zoralabs/coins-sdk");
vi.mock("../lib/config.js", () => ({
  getApiKey: vi.fn(),
  getPrivateKey: vi.fn(),
}));
vi.mock("../lib/render.js", () => ({
  renderOnce: vi.fn(),
  renderLive: vi.fn().mockResolvedValue(undefined),
}));

import { formatTradeJson, extractSectionError } from "./profile.jsx";
import type { TradeNode } from "../components/ProfileTradesView.js";

const makeTrade = (overrides = {}): TradeNode => ({
  transactionHash: "0xabc123",
  blockTimestamp: "2025-01-15T10:30:00Z",
  coinAmount: "1000000000000000000000",
  swapActivityType: "BUY",
  coin: {
    address: "0x1234567890abcdef1234567890abcdef12345678",
    name: "TestCoin",
    symbol: "TC",
    coinType: "CREATOR",
  },
  currencyAmountWithPrice: { amountUsd: "25.50" },
  ...overrides,
});

describe("formatTradeJson", () => {
  it("formats a complete trade", () => {
    const result = formatTradeJson(makeTrade(), 1);
    expect(result).toEqual({
      rank: 1,
      side: "BUY",
      coinName: "TestCoin",
      coinSymbol: "TC",
      coinType: "CREATOR",
      coinAddress: "0x1234567890abcdef1234567890abcdef12345678",
      coinAmount: "1000000000000000000000",
      amountUsd: "25.50",
      transactionHash: "0xabc123",
      timestamp: "2025-01-15T10:30:00Z",
    });
  });

  it("returns null fields when coin data is missing", () => {
    const result = formatTradeJson(makeTrade({ coin: undefined }), 2);
    expect(result.coinName).toBeNull();
    expect(result.coinSymbol).toBeNull();
    expect(result.coinType).toBeNull();
    expect(result.coinAddress).toBeNull();
    expect(result.rank).toBe(2);
  });

  it("falls back to UNKNOWN when swapActivityType is missing", () => {
    const result = formatTradeJson(
      makeTrade({ swapActivityType: undefined }),
      1,
    );
    expect(result.side).toBe("UNKNOWN");
  });

  it("returns null amountUsd when missing", () => {
    const result = formatTradeJson(
      makeTrade({ currencyAmountWithPrice: {} }),
      1,
    );
    expect(result.amountUsd).toBeNull();
  });

  it("formats SELL trades", () => {
    const result = formatTradeJson(makeTrade({ swapActivityType: "SELL" }), 3);
    expect(result.side).toBe("SELL");
    expect(result.rank).toBe(3);
  });
});

describe("extractSectionError", () => {
  it("returns error message from rejected promise", () => {
    const result: PromiseSettledResult<{ error?: unknown; data?: unknown }> = {
      status: "rejected",
      reason: new Error("Network timeout"),
    };
    expect(extractSectionError(result)).toBe("Network timeout");
  });

  it("stringifies non-Error rejection reasons", () => {
    const result: PromiseSettledResult<{ error?: unknown; data?: unknown }> = {
      status: "rejected",
      reason: "something went wrong",
    };
    expect(extractSectionError(result)).toBe("something went wrong");
  });

  it("returns error message from fulfilled result with API error", () => {
    const result: PromiseSettledResult<{ error?: unknown; data?: unknown }> = {
      status: "fulfilled",
      value: { error: { error: "Rate limited" } },
    };
    expect(extractSectionError(result)).toBe("Rate limited");
  });

  it("returns undefined for successful result", () => {
    const result: PromiseSettledResult<{ error?: unknown; data?: unknown }> = {
      status: "fulfilled",
      value: { data: { some: "data" } },
    };
    expect(extractSectionError(result)).toBeUndefined();
  });
});
