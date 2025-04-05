import { describe, expect, it } from "vitest";
import { getCoins } from "../src";

describe("Coins Offchain Details", () => {
  it("getCoins", async () => {
    const coinDetails = await getCoins({
      coins: [
        {
          collectionAddress: "0xb428d96334a5e0005c173dc74747ce2b25db8778",
          chainId: 8453,
        },
        {
          collectionAddress: "0xc93f58e8b21794d94c938bcca200b0c65919d45b",
          chainId: 8453,
        },
      ],
    });

    expect(coinDetails.data?.zora20Tokens?.length).to.equal(2);
    expect(coinDetails.data?.zora20Tokens?.[0]?.address).to.equal(
      "0xb428d96334a5e0005c173dc74747ce2b25db8778",
    );
    expect(coinDetails.data?.zora20Tokens?.[1]?.address).to.equal(
      "0xc93f58e8b21794d94c938bcca200b0c65919d45b",
    );
  });
});
