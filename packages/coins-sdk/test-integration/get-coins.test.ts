import { describe, it } from "vitest";
import { getCoins } from "../src";

describe("Coins Offchain Details", () => {
  it("getCoins", async () => {
    const coinDetails = await getCoins({
      coinAddresses: ["0xb428d96334a5e0005c173dc74747ce2b25db8778"],
      chainId: 8453,
    });

    coinDetails.data?.zora20Tokens?.forEach((token) => {
      console.log(token.address);
    });
  });
});
