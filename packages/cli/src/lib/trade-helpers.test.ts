import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { parseEther } from "viem";
import { printQuote, printTradeResult } from "./trade-helpers.js";

const baseQuoteInfo = {
  coinName: "TestCoin",
  coinSymbol: "TEST",
  coinType: "Creator Coin",
  address: "0x1234567890abcdef1234567890abcdef12345678",
  amountIn: parseEther("0.5"),
  inputTokenSymbol: "ETH",
  inputTokenDecimals: 18,
  amountOut: parseEther("1000").toString(),
  slippagePct: 1,
};

const baseTradeResultInfo = {
  coinName: "TestCoin",
  coinSymbol: "TEST",
  coinType: "Creator Coin",
  address: "0x1234567890abcdef1234567890abcdef12345678",
  amountIn: parseEther("0.5"),
  inputTokenSymbol: "ETH",
  inputTokenDecimals: 18,
  receivedAmountOut: parseEther("1000"),
  txHash: "0xabc123",
};

describe("printQuote", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  });

  afterEach(() => {
    logSpy.mockRestore();
  });

  it("includes USD annotation when amountUsd is provided", () => {
    printQuote(false, { ...baseQuoteInfo, amountUsd: "~$1,000.00" });

    const amountLine = logSpy.mock.calls.find(
      (call) => typeof call[0] === "string" && call[0].includes("Amount"),
    );
    expect(amountLine).toBeDefined();
    expect(amountLine![0]).toContain("(~$1,000.00)");
  });

  it("omits USD annotation when amountUsd is undefined", () => {
    printQuote(false, baseQuoteInfo);

    const amountLine = logSpy.mock.calls.find(
      (call) => typeof call[0] === "string" && call[0].includes("Amount"),
    );
    expect(amountLine).toBeDefined();
    expect(amountLine![0]).not.toContain("(");
  });

  it("shows ETH amount and symbol in the amount line", () => {
    printQuote(false, baseQuoteInfo);

    const amountLine = logSpy.mock.calls.find(
      (call) => typeof call[0] === "string" && call[0].includes("Amount"),
    );
    expect(amountLine![0]).toContain("0.5");
    expect(amountLine![0]).toContain("ETH");
  });

  it("json output does not include amountUsd", () => {
    const exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation(() => undefined as never);

    printQuote(true, { ...baseQuoteInfo, amountUsd: "~$1,000.00" });

    const jsonCall = logSpy.mock.calls[0]?.[0];
    expect(jsonCall).toBeDefined();
    const parsed = JSON.parse(jsonCall as string);
    expect(parsed.amountUsd).toBeUndefined();
    expect(parsed.spend).toBeDefined();

    exitSpy.mockRestore();
  });
});

describe("printTradeResult", () => {
  let logSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
  });

  afterEach(() => {
    logSpy.mockRestore();
  });

  it("includes USD annotation when amountUsd is provided", () => {
    printTradeResult(false, {
      ...baseTradeResultInfo,
      amountUsd: "~$1,000.00",
    });

    const spentLine = logSpy.mock.calls.find(
      (call) => typeof call[0] === "string" && call[0].includes("Spent"),
    );
    expect(spentLine).toBeDefined();
    expect(spentLine![0]).toContain("(~$1,000.00)");
  });

  it("omits USD annotation when amountUsd is undefined", () => {
    printTradeResult(false, baseTradeResultInfo);

    const spentLine = logSpy.mock.calls.find(
      (call) => typeof call[0] === "string" && call[0].includes("Spent"),
    );
    expect(spentLine).toBeDefined();
    expect(spentLine![0]).not.toContain("(");
  });

  it("shows formatted ETH amount in spent line", () => {
    printTradeResult(false, baseTradeResultInfo);

    const spentLine = logSpy.mock.calls.find(
      (call) => typeof call[0] === "string" && call[0].includes("Spent"),
    );
    expect(spentLine![0]).toContain("0.5");
    expect(spentLine![0]).toContain("ETH");
  });

  it("json output does not include amountUsd", () => {
    const exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation(() => undefined as never);

    printTradeResult(true, {
      ...baseTradeResultInfo,
      amountUsd: "~$1,000.00",
    });

    const jsonCall = logSpy.mock.calls[0]?.[0];
    const parsed = JSON.parse(jsonCall as string);
    expect(parsed.amountUsd).toBeUndefined();
    expect(parsed.spent).toBeDefined();
    expect(parsed.received).toBeDefined();

    exitSpy.mockRestore();
  });
});
