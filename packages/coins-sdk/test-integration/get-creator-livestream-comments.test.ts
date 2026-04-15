import { describe, expect, it } from "vitest";
import { getCreatorLivestreamComments } from "../src";

describe("getCreatorLivestreamComments", () => {
  it("returns livestream comments for a known coin", async () => {
    const result = await getCreatorLivestreamComments({
      address: "0x3a5df03dd1a001d7055284c2c2c147cbbc78d142",
      chain: 8453,
    });

    expect(result.data).toBeDefined();
  });

  it("supports pagination with count parameter", async () => {
    const result = await getCreatorLivestreamComments({
      address: "0x3a5df03dd1a001d7055284c2c2c147cbbc78d142",
      chain: 8453,
      count: 5,
    });

    expect(result.data).toBeDefined();
  });
});
