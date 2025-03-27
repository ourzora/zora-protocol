import { describe, it } from "vitest";
import { getCoinsTopVolume24h, getCoinComments } from "../src";

describe("Coin Onchain Info", () => {
  it("gets latest coin info mainnet with USDC", async () => {
    const coinDetails = await getCoinsTopVolume24h();
    console.log({ coinDetails });
  });
  it("gets latest coin info mainnet debug", async () => {
    const coinComments = await getCoinComments({
      address: "0x72fd6907113101e6e32cee25d5909868504d67f1",
    });

    console.log({ coinComments });
  });
});
