import { describe, it } from "vitest";
import { getOnchainCoinDetails } from "../src";

import { createPublicClient, http } from "viem";
import { base } from "viem/chains";
const publicClient = createPublicClient({
  chain: base,
  transport: http(),
});
describe("Coin Onchain Info", () => {
  it("gets latest coin info mainnet with USDC", async () => {
    const coinDetails = await getOnchainCoinDetails({
      coin: "0xa595ca967f5b82ff32e644792d66e512ac2b7de6",
      publicClient,
    });
    console.log({ coinDetails });
  });
  it("gets latest coin info mainnet debug", async () => {
    const coinDetails = await getOnchainCoinDetails({
      coin: "0x72fd6907113101e6e32cee25d5909868504d67f1",
      publicClient,
    });
    console.log({ coinDetails });
  });
});
