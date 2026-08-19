import { describe, expect, it } from "vitest";
import { getCoinPriceHistory } from "../src";

describe("getCoinPriceHistory", () => {
  it("returns price history for a known coin", async () => {
    const result = await getCoinPriceHistory({
      address: "0x3a5df03dd1a001d7055284c2c2c147cbbc78d142",
      chain: 8453,
    });

    expect(result.data).toBeDefined();
    expect(result.data?.zora20Token).toBeDefined();
  });
});
