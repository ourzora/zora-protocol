import { describe, expect, it } from "vitest";
import { getCoin, getCoinsNew } from "../src";
import { isAddress } from "viem";

describe("Coin Offchain Details", () => {
  it("gets the offchain coin details", async () => {
    const coinDetails = await getCoin({
      address: "0xb428d96334a5e0005c173dc74747ce2b25db8778",
    });
    expect(coinDetails.data?.zora20Token?.createdAt).to.equal(
      "2025-03-09T02:37:45",
    );
  });
  it("gets the offchain explore query", async () => {
    const newCoins = await getCoinsNew();
    const newAddress = newCoins.data?.exploreList?.edges?.[0]?.node?.address;
    expect(isAddress(newAddress!)).to.eq(true);
  });
});
