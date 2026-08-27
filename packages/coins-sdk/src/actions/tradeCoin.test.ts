import { describe, it, expect, vi } from "vitest";
import { createQuote } from "./tradeCoin";
import * as client from "../client";

vi.mock("../client", () => ({
  postQuote: vi.fn(),
}));

vi.mock("@zoralabs/protocol-deployments", () => ({
  permit2ABI: [],
  permit2Address: { 8453: "0x000" },
}));

describe("tradeCoin actions", () => {
  describe("createQuote", () => {
    it("should pass referrer to postQuote", async () => {
      const mockPostQuote = vi.mocked(client.postQuote);
      mockPostQuote.mockResolvedValue({
        data: {
          call: {
            target: "0x123",
            data: "0x456",
            value: "0",
          },
        },
      } as any);

      const tradeParameters = {
        sell: { type: "eth" } as const,
        buy: { type: "erc20", address: "0xToken" as const } as const,
        amountIn: BigInt(1000),
        slippage: 0.01,
        sender: "0xSender" as const,
        referrer: "0xReferrer",
      };

      await createQuote(tradeParameters);

      expect(mockPostQuote).toHaveBeenCalledWith({
        body: {
          tokenIn: tradeParameters.sell,
          tokenOut: tradeParameters.buy,
          amountIn: "1000",
          slippage: 0.01,
          chainId: 8453, // base.id
          sender: "0xSender",
          recipient: "0xSender",
          signatures: undefined,
          referrer: "0xReferrer",
        },
      });
    });

    it("should handle missing referrer", async () => {
      const mockPostQuote = vi.mocked(client.postQuote);
      mockPostQuote.mockResolvedValue({
        data: {
          call: {
            target: "0x123",
            data: "0x456",
            value: "0",
          },
        },
      } as any);

      const tradeParameters = {
        sell: { type: "eth" } as const,
        buy: { type: "erc20", address: "0xToken" as const } as const,
        amountIn: BigInt(1000),
        slippage: 0.01,
        sender: "0xSender" as const,
      };

      await createQuote(tradeParameters);

      expect(mockPostQuote).toHaveBeenCalledWith({
        body: {
          tokenIn: tradeParameters.sell,
          tokenOut: tradeParameters.buy,
          amountIn: "1000",
          slippage: 0.01,
          chainId: 8453, // base.id
          sender: "0xSender",
          recipient: "0xSender",
          signatures: undefined,
          referrer: undefined,
        },
      });
    });
  });
});
